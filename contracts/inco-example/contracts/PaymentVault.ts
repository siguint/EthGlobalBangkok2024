import { ethers } from "ethers";
import { TFHE } from "fhevm";

// Interfaces
interface IService {
  subscriptionPrice: TFHE.euint64;
  receiver: string;
  isActive: boolean;
}

interface IPaymentVault {
  owner: string;
  token: string;
  totalDeposits: TFHE.euint64;
  nextServiceId: number;
  services: Map<number, IService>;
  deposits: Map<number, Map<TFHE.eaddress, TFHE.euint64>>;
  lastPaymentTimestamp: Map<number, Map<TFHE.eaddress, number>>;
  serviceTotalDeposits: Map<number, TFHE.euint64>;
}

// Events
interface IServiceRegistered {
  serviceId: number;
  receiver: string;
}

interface IServicePriceChanged {
  serviceId: number;
}

interface IServiceDeactivated {
  serviceId: number;
}

interface IDeposited {
  serviceId: number;
  depositor: TFHE.eaddress;
}

interface IWithdrawn {
  serviceId: number;
  receiver: string;
}

export class PaymentVault {
  private state: IPaymentVault;
  private readonly SUBSCRIPTION_PERIOD = 30 * 24 * 60 * 60; // 30 days in seconds

  constructor(tokenAddress: string) {
    this.state = {
      owner: ethers.constants.AddressZero,
      token: tokenAddress,
      totalDeposits: TFHE.asEuint64(0),
      nextServiceId: 0,
      services: new Map(),
      deposits: new Map(),
      lastPaymentTimestamp: new Map(),
      serviceTotalDeposits: new Map()
    };
  }

  // Modifiers
  private onlyOwner(sender: string) {
    if (sender !== this.state.owner) {
      throw new Error("Only owner can call this function");
    }
  }

  private onlyServiceReceiver(serviceId: number, sender: string) {
    const service = this.state.services.get(serviceId);
    if (!service || service.receiver !== sender) {
      throw new Error("Only service receiver can call this function");
    }
  }

  // Main functions
  public async registerService(
    receiver: string,
    encryptedPrice: TFHE.einput,
    priceProof: Uint8Array,
    sender: string
  ): Promise<number> {
    this.onlyOwner(sender);

    const serviceId = this.state.nextServiceId++;
    const subscriptionPrice = await TFHE.asEuint64(encryptedPrice, priceProof);

    this.state.services.set(serviceId, {
      subscriptionPrice,
      receiver,
      isActive: true
    });

    // Emit ServiceRegistered event
    return serviceId;
  }

  public async setSubscriptionPrice(
    serviceId: number,
    encryptedNewPrice: TFHE.einput,
    priceProof: Uint8Array,
    sender: string
  ): Promise<void> {
    this.onlyServiceReceiver(serviceId, sender);

    const service = this.state.services.get(serviceId);
    if (!service || !service.isActive) {
      throw new Error("Service not active");
    }

    service.subscriptionPrice = await TFHE.asEuint64(encryptedNewPrice, priceProof);
    this.state.services.set(serviceId, service);

    // Emit ServicePriceChanged event
  }

  public deactivateService(serviceId: number, sender: string): void {
    this.onlyOwner(sender);

    const service = this.state.services.get(serviceId);
    if (!service || !service.isActive) {
      throw new Error("Service not active");
    }

    service.isActive = false;
    this.state.services.set(serviceId, service);

    // Emit ServiceDeactivated event
  }

  public async subscribe(
    serviceId: number,
    encryptedSubscriber: TFHE.einput,
    subscriberProof: Uint8Array,
    sender: string
  ): Promise<void> {
    const service = this.state.services.get(serviceId);
    if (!service || !service.isActive) {
      throw new Error("Service not active");
    }

    const subscriber = await TFHE.asEaddress(encryptedSubscriber, subscriberProof);
    const price = service.subscriptionPrice;

    // Handle token transfer
    await this.handleTokenTransfer(sender, price);

    // Update deposits
    const userDeposits = this.state.deposits.get(serviceId) || new Map();
    const currentDeposit = userDeposits.get(subscriber) || TFHE.asEuint64(0);
    userDeposits.set(subscriber, await TFHE.add(currentDeposit, price));
    this.state.deposits.set(serviceId, userDeposits);

    // Update service total deposits
    const currentServiceDeposits = this.state.serviceTotalDeposits.get(serviceId) || TFHE.asEuint64(0);
    this.state.serviceTotalDeposits.set(serviceId, await TFHE.add(currentServiceDeposits, price));

    // Update total deposits
    this.state.totalDeposits = await TFHE.add(this.state.totalDeposits, price);

    // Update timestamp
    const timestamps = this.state.lastPaymentTimestamp.get(serviceId) || new Map();
    timestamps.set(subscriber, Math.floor(Date.now() / 1000));
    this.state.lastPaymentTimestamp.set(serviceId, timestamps);

    // Emit Deposited event
  }

  public async withdraw(
    serviceId: number,
    encryptedAmount: TFHE.einput,
    amountProof: Uint8Array,
    sender: string
  ): Promise<void> {
    this.onlyServiceReceiver(serviceId, sender);

    const amount = await TFHE.asEuint64(encryptedAmount, amountProof);
    const serviceTotalDeposit = this.state.serviceTotalDeposits.get(serviceId) || TFHE.asEuint64(0);
    
    const canTransfer = await TFHE.le(amount, serviceTotalDeposit);
    const transferValue = await TFHE.select(canTransfer, amount, TFHE.asEuint64(0));

    // Handle token transfer
    await this.handleTokenWithdraw(sender, transferValue);

    // Update deposits
    this.state.serviceTotalDeposits.set(serviceId, await TFHE.sub(serviceTotalDeposit, amount));
    this.state.totalDeposits = await TFHE.sub(this.state.totalDeposits, amount);

    // Emit Withdrawn event
  }

  public async isSubscriptionActive(
    serviceId: number,
    encryptedSubscriber: TFHE.einput,
    subscriberProof: Uint8Array
  ): Promise<boolean> {
    const service = this.state.services.get(serviceId);
    if (!service || !service.isActive) {
      return false;
    }

    const subscriber = await TFHE.asEaddress(encryptedSubscriber, subscriberProof);
    const timestamps = this.state.lastPaymentTimestamp.get(serviceId);
    if (!timestamps) {
      return false;
    }

    const lastPayment = timestamps.get(subscriber);
    if (!lastPayment) {
      return false;
    }

    return Math.floor(Date.now() / 1000) <= lastPayment + this.SUBSCRIPTION_PERIOD;
  }

  private async handleTokenTransfer(from: string, amount: TFHE.euint64): Promise<void> {
    // Implement token transfer logic
  }

  private async handleTokenWithdraw(to: string, amount: TFHE.euint64): Promise<void> {
    // Implement token withdrawal logic
  }
} 