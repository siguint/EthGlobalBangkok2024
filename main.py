import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, CallbackQueryHandler
from dotenv import load_dotenv
import os
import sqlite3
from web3 import Web3

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

# Initialize Web3
w3 = Web3(Web3.HTTPProvider(os.getenv('ETHEREUM_RPC_URL')))
CONTRACT_ADDRESS = os.getenv('CONTRACT_ADDRESS')
CONTRACT_ABI = [
    # Add your contract ABI here
]

# Database initialization
def init_db():
    conn = sqlite3.connect('bot.db')
    c = conn.cursor()
    
    # First, check if the channels table exists
    c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='channels'")
    table_exists = c.fetchone() is not None
    
    if not table_exists:
        # Create new table if it doesn't exist
        c.execute('''CREATE TABLE channels
                     (channel_id TEXT PRIMARY KEY, added_by TEXT, contract_address TEXT)''')
    else:
        # Check if contract_address column exists
        cursor = c.execute('PRAGMA table_info(channels)')
        columns = [column[1] for column in cursor.fetchall()]
        if 'contract_address' not in columns:
            c.execute('ALTER TABLE channels ADD COLUMN contract_address TEXT')
    
    # Create subscriptions table if it doesn't exist
    c.execute('''CREATE TABLE IF NOT EXISTS subscriptions
                 (user_id TEXT, channel_id TEXT,
                  PRIMARY KEY (user_id, channel_id))''')
    
    conn.commit()
    conn.close()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await context.bot.send_message(
        chat_id=update.effective_chat.id,
        text="Welcome! Use /add_channel to add your channel or /subscribe to view available channels."
    )

async def verify_admin(bot, channel_username, user_id):
    try:
        # Check if user is admin
        user_member = await bot.get_chat_member(chat_id=channel_username, user_id=user_id)
        user_is_admin = user_member.status in ['creator', 'administrator']
        
        # Check if bot is admin
        bot_member = await bot.get_chat_member(
            chat_id=channel_username, 
            user_id=bot.id
        )
        bot_is_admin = bot_member.status in ['administrator']
        
        if not user_is_admin:
            raise Exception("User is not an admin of the channel")
        if not bot_is_admin:
            raise Exception("Bot is not an admin of the channel")
            
        return True
        
    except Exception as e:
        logging.error(f"Error verifying admin status: {e}")
        return False

async def add_channel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.args:
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Please provide a channel username (e.g., /add_channel @channel)"
        )
        return

    channel_username = context.args[0]
    if not channel_username.startswith('@'):
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Channel username must start with @ symbol"
        )
        return
    
    conn = sqlite3.connect('bot.db')
    c = conn.cursor()

    # Fetch existing channels and check if channel already exists
    existing_channels = [channel[0] for channel in c.execute("SELECT channel_id FROM channels").fetchall()]
    if channel_username in existing_channels:
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="This channel is already in the subscription list!"
        )
        return

    user_id = update.effective_user.id
    
    # Verify if user and bot are admins of the channel
    is_admin = await verify_admin(context.bot, channel_username, user_id)
    if not is_admin:
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="Error: Both you and the bot must be administrators of the channel. "
                 "Please make sure to add the bot as an administrator first!"
        )
        return

    # Generate smart contract link
    contract = w3.eth.contract(address=CONTRACT_ADDRESS, abi=CONTRACT_ABI)
    contract_link = f"https://etherscan.io/address/{CONTRACT_ADDRESS}"

    try:
        c.execute("INSERT INTO channels (channel_id, added_by, contract_address) VALUES (?, ?, ?)",
                 (channel_username, str(user_id), CONTRACT_ADDRESS))
        conn.commit()
        
        # Create message with contract link
        message_text = (
            f"Successfully added channel {channel_username} to subscription list!\n\n"
            f"Please complete the registration by interacting with the smart contract:\n"
            f"{contract_link}\n\n"
            f"Once the transaction is confirmed, your channel will be activated for subscriptions."
        )
        
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text=message_text,
            disable_web_page_preview=True
        )
    except sqlite3.IntegrityError:
        await context.bot.send_message(
            chat_id=update.effective_chat.id, 
            text="This channel is already in the subscription list!"
        )
    finally:
        conn.close()

async def subscribe(update: Update, context: ContextTypes.DEFAULT_TYPE):
    conn = sqlite3.connect('bot.db')
    c = conn.cursor()
    c.execute("SELECT channel_id FROM channels")
    channels = c.fetchall()
    conn.close()

    if not channels:
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text="No channels available for subscription yet."
        )
        return

    keyboard = []
    for channel in channels:
        keyboard.append([InlineKeyboardButton(channel[0], callback_data=f"sub_{channel[0]}")])

    reply_markup = InlineKeyboardMarkup(keyboard)
    await context.bot.send_message(
        chat_id=update.effective_chat.id,
        text="Select a channel to subscribe:",
        reply_markup=reply_markup
    )

async def handle_subscription(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    channel_id = query.data.replace("sub_", "")
    user_id = str(update.effective_user.id)

    conn = sqlite3.connect('bot.db')
    c = conn.cursor()
    try:
        c.execute("INSERT INTO subscriptions (user_id, channel_id) VALUES (?, ?)",
                 (user_id, channel_id))
        conn.commit()
        await query.answer(f"Successfully subscribed to {channel_id}")
    except sqlite3.IntegrityError:
        await query.answer("You're already subscribed to this channel!")
    finally:
        conn.close()

if __name__ == '__main__':
    load_dotenv()
    init_db()
    application = ApplicationBuilder().token(os.getenv('TELEGRAM_BOT_TOKEN')).build()
    
    # Add handlers
    application.add_handler(CommandHandler('start', start))
    application.add_handler(CommandHandler('add_channel', add_channel))
    application.add_handler(CommandHandler('subscribe', subscribe))
    application.add_handler(CallbackQueryHandler(handle_subscription, pattern="^sub_"))
    
    application.run_polling()