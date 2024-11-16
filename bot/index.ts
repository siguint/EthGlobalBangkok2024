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
    
    const contractArtifact = require('../contracts/inco-example/artifacts/contracts/PaymentVault.sol/PaymentVault.json');
    this.paymentVault = new ethers.Contract(
      process.env.CONTRACT_ADDRESS!,
      contractArtifact.abi,
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

      const [_, channelUsername, receiverAddress] = args;
      
      if (!channelUsername.startsWith('@')) {
        await ctx.reply('Channel username must start with @ symbol');
        return;
      }

      try {
        ethers.getAddress(receiverAddress); // Validate address format
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
          [channelUsername, ctx.from.id.toString(), receiverAddress]
        );

        const explorerLink = `https://explorer.rivest.inco.org/address/${process.env.CONTRACT_ADDRESS}`;
        await ctx.reply(
          `Successfully added channel ${channelUsername} to subscription list!\n\n` +
          `Contract address: ${process.env.CONTRACT_ADDRESS}\n` +
          `Service admin: ${receiverAddress}\n` +
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

        // Send user to encryption page
        const encryptionUrl = `${process.env.ENCRYPTION_URL}?channel=${channelId}&contract=${channel.contract_address}`;
        
        await ctx.reply(
          'Please visit this URL to encrypt your address:\n\n' +
          `${encryptionUrl}\n\n` +
          'After encryption, use the /complete_subscription command with the encrypted subscriber address and proof:\n\n' +
          '/complete_subscription <channel id> <encrypted_address>\n' +
          'Then send the proof as a .txt file'
        );

        await ctx.answerCbQuery('Please check the instructions sent in chat');

      } catch (error) {
        console.error('Subscription error:', error);
        await ctx.answerCbQuery('Error processing subscription. Please try again.');
      }
    });

    // Handle subscription completion
    this.bot.command('complete_subscription', async (ctx) => {
      const userId = ctx.from.id.toString();
      
      // Get the full message text after the command
      const fullText = ctx.message.text.substring('/complete_subscription'.length).trim();
      
      // Use a regex to match just the channel ID and encrypted address
      const match = fullText.match(/^(\S+)\s+(\S+)$/);
      
      if (!match) {
        await ctx.reply(
          'Please provide: /complete_subscription <channel_id> <encrypted_address>\n' +
          'Then send the proof as a .txt file'
        );
        return;
      }

      const [_, channelId, encryptedAddress] = match;

      try {
        await ctx.reply('Please send the proof as a .txt file...');
        
        // Set up a one-time document listener for the proof
        const proof = await new Promise<string>((resolve, reject) => {
          const timeout = setTimeout(() => {
            reject(new Error('Proof submission timeout'));
          }, 120000);

          // Create document handler middleware
          const middleware = this.bot.on('document', async (ctx) => {
            if (!ctx.message || !('document' in ctx.message)) {
              return;
            }

            if (ctx.from?.id === parseInt(userId)) {
              try {
                const doc = ctx.message.document;
                console.log('Processing document:', doc);

                if (!doc.mime_type?.startsWith('text/')) {
                  await ctx.reply('Please send the proof as a .txt file');
                  return;
                }

                const file = await ctx.telegram.getFile(doc.file_id);
                console.log('Got file:', file);

                if (!file.file_path) throw new Error('Could not get file path');

                const fileUrl = `https://api.telegram.org/file/bot${process.env.TELEGRAM_BOT_TOKEN}/${file.file_path}`;
                console.log('Fetching from URL:', fileUrl);

                const response = await fetch(fileUrl);
                const proofText = await response.text();
                console.log('Got proof text:', proofText.substring(0, 50) + '...');

                clearTimeout(timeout);
                resolve(proofText);
              } catch (error) {
                clearTimeout(timeout);
                reject(error instanceof Error ? error : new Error(String(error)));
              }
            }
          });
        });

        // Parse proof from text file
        const proofText = proof.trim();
        
        // If proof is hex
        if (proofText.startsWith('0x')) {
            // Pass hex directly
            await this.paymentVault.subscribe(encryptedAddress, proofText);
        } else {
          console.error('Proof is not hex:', proofText);
          await ctx.reply('Invalid proof format. Proof must be a hex string starting with 0x');
          return;
        }

        await this.db.run(
          'INSERT INTO subscriptions (user_id, channel_id) VALUES (?, ?)',
          [userId, channelId]
        );

        await ctx.reply('Successfully subscribed to the channel!');
      } catch (error) {
        console.error('Subscription completion error:', error);
        await ctx.reply('Error completing subscription. Please try again.');
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