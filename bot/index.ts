import { Telegraf, Context } from 'telegraf';
import { ethers } from 'ethers';
import { config } from 'dotenv';
import { Message } from 'telegraf/types';
import sqlite3 from 'sqlite3';
import { Database, open } from 'sqlite';
// import type { FhevmInstance } from "fhevmjs";

const { createInstance, FhevmInstance } = require("fhevmjs");

let fhevmInstance: typeof FhevmInstance | null = null;

const createFhevmInstance = async () => {
  if (!fhevmInstance) {
    fhevmInstance = await createInstance({
      chainId: 21097,
      networkUrl: "https://validator.rivest.inco.org/",
      gatewayUrl: "https://gateway.rivest.inco.org/",
      aclAddress: "0x2Fb4341027eb1d2aD8B5D9708187df8633cAFA92",
    });
  }
  return fhevmInstance;
};

const getFhevmInstance = async () => {
  if (!fhevmInstance) {
    fhevmInstance = await createFhevmInstance();
  }
  return fhevmInstance;
};

// Load environment variables
config();

interface BotContext extends Context {
  db: Database;
}

class TelegramBot {
  private bot: Telegraf<BotContext>;
  private provider: ethers.Provider;
  private paymentVault: ethers.Contract;
  private db!: Database;

  constructor() {
    this.bot = new Telegraf<BotContext>(process.env.TELEGRAM_BOT_TOKEN!);
    this.provider = new ethers.JsonRpcProvider(process.env.ETHEREUM_RPC_URL);
    this.paymentVault = new ethers.Contract(
      process.env.CONTRACT_ADDRESS!,
      require('../contracts/inco-example/artifacts/contracts/PaymentVault.sol/PaymentVault.json'),
      this.provider
    );
    
    this.initializeBot();
  }

  private async initializeDatabase() {
    this.db = await open({
      filename: 'bot.db',
      driver: sqlite3.Database
    });

    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS channels (
        channel_id TEXT PRIMARY KEY,
        added_by TEXT,
        contract_address TEXT
      )`);

    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS subscriptions (
        user_id TEXT,
        channel_id TEXT,
        PRIMARY KEY (user_id, channel_id)
      )`);
  }

  private async verifyAdmin(channelUsername: string, userId: number): Promise<boolean> {
    try {
      const chatMember = await this.bot.telegram.getChatMember(channelUsername, userId);
      return ['creator', 'administrator'].includes(chatMember.status);
    } catch (error) {
      console.error('Error verifying admin status:', error);
      return false;
    }
  }

  private initializeBot() {
    // Start command
    this.bot.command('start', async (ctx) => {
      await ctx.reply(
        'Welcome! Use /add_channel to add your channel or /subscribe to view available channels.'
      );
    });

    // Add channel command
    this.bot.command('add_channel', async (ctx) => {
      const args = ctx.message.text.split(' ');
      if (args.length !== 3) {
        await ctx.reply(
          'Please provide channel username and contract address\n' +
          'Usage: /add_channel @channel 0x...'
        );
        return;
      }

      const [_, channelUsername, contractAddress] = args;
      
      if (!channelUsername.startsWith('@')) {
        await ctx.reply('Channel username must start with @ symbol');
        return;
      }

      try {
        ethers.getAddress(contractAddress); // Validate address format
      } catch {
        await ctx.reply('Invalid contract address format');
        return;
      }

      const isAdmin = await this.verifyAdmin(channelUsername, ctx.from.id);
      if (!isAdmin) {
        await ctx.reply(
          'Error: Both you and the bot must be administrators of the channel. ' +
          'Please make sure to add the bot as an administrator first!'
        );
        return;
      }

      try {
        await this.db.run(
          'INSERT INTO channels (channel_id, added_by, contract_address) VALUES (?, ?, ?)',
          [channelUsername, ctx.from.id.toString(), contractAddress]
        );

        const explorerLink = `https://explorer.rivest.inco.org/address/${contractAddress}`;
        await ctx.reply(
          `Successfully added channel ${channelUsername} to subscription list!\n\n` +
          `Contract address: ${contractAddress}\n` +
          `View on Explorer: ${explorerLink}\n\n` +
          `Your channel is now ready for subscriptions.`,
        );
      } catch (error) {
        if ((error as any).code === 'SQLITE_CONSTRAINT') {
          await ctx.reply('This channel is already in the subscription list!');
        } else {
          console.error('Database error:', error);
          await ctx.reply('An error occurred while adding the channel.');
        }
      }
    });

    // Subscribe command
    this.bot.command('subscribe', async (ctx) => {
      const channels = await this.db.all('SELECT channel_id FROM channels');
      
      if (!channels.length) {
        await ctx.reply('No channels available for subscription yet.');
        return;
      }

      const keyboard = channels.map(channel => [{
        text: channel.channel_id,
        callback_data: `sub_${channel.channel_id}`
      }]);

      await ctx.reply('Select a channel to subscribe:', {
        reply_markup: {
          inline_keyboard: keyboard
        }
      });
    });

    // Handle subscription callbacks
    this.bot.action(/^sub_(.+)$/, async (ctx) => {
      const channelId = ctx.match[1];
      const userId = ctx.from.id.toString();

      try {
        const channel = await this.db.get(
          'SELECT contract_address FROM channels WHERE channel_id = ?',
          [channelId]
        );

        if (!channel) {
          await ctx.answerCbQuery('Channel not found!');
          return;
        }

        // Get FHEVM instance
        const instance = await getFhevmInstance();
        
        // Create encrypted input for the user ID
        const input = instance.createEncryptedInput(
          channel.contract_address,
          this.provider
        );
        
        // Encrypt the user ID
        input.add64(BigInt(userId));
        const encryptedSubscriber = input.encrypt();

        // Call smart contract
        const tx = await this.paymentVault.subscribe(
          channelId,
          encryptedSubscriber
        );
        await tx.wait();

        await this.db.run(
          'INSERT INTO subscriptions (user_id, channel_id) VALUES (?, ?)',
          [userId, channelId]
        );

        await ctx.answerCbQuery(`Successfully subscribed to ${channelId}`);
      } catch (error) {
        console.error('Subscription error:', error);
        await ctx.answerCbQuery('Error processing subscription. Please try again.');
      }
    });
  }

  public async start() {
    await this.initializeDatabase();
    this.bot.launch();

    process.once('SIGINT', () => this.bot.stop('SIGINT'));
    process.once('SIGTERM', () => this.bot.stop('SIGTERM'));
  }
}

// Start the bot
const bot = new TelegramBot();
bot.start().catch(console.error); 