require 'sinatra'
require 'json'
require 'securerandom'
require 'net/http'
require 'cgi'

# check and set environment variables
branch = ENV["BRANCH"]
if branch == nil
    puts "Warning: BRANCH environment variable not set, defaulting to master"
    branch = "master"
end

url_validity = ENV["URL_VALIDITY"].to_i
if url_validity == 0
    puts "Warning: URL_VALIDITY environment variable not set or 0, defaulting to 120 seconds"
    url_validity = 120
end

host = ENV["HOST"]
if host == nil
    puts "Please set the HOST environment variable"
    exit 1
end

if ENV["WEBHOOK_SECRET"] == nil
    puts "Please set the WEBHOOK_SECRET environment variable"
    exit 1
end

stack_dir = ENV["STACK_DIR"]
if stack_dir == nil
    puts "Please set the STACK_DIR environment variable"
    exit 1
end

stack_name = ENV["STACK_NAME"]
if stack_name == nil
    puts "Please set the STACK_NAME environment variable"
    exit 1
end

ssh_host = ENV["SSH_HOST"]
if ssh_host == nil
    puts "Please set the SSH_HOST environment variable"
    exit 1
end

ssh_user = ENV["SSH_USER"]
if ssh_user == nil
    puts "Please set the SSH_USER environment variable"
    exit 1
end

ssh_port = ENV["SSH_PORT"]
if ssh_port == nil
    puts "Please set the SSH_PORT environment variable"
    exit 1
end

if ENV["TELEGRAM_TOKEN"] == nil
    puts "Please set the TELEGRAM_TOKEN environment variable"
    exit 1
end

if ENV["TELEGRAM_CHAT_ID"] == nil
    puts "Please set the TELEGRAM_CHAT_ID environment variable"
    exit 1
end

port = 9999
ssh_key_path = "/app/ssh_key"

valid_urls = []

# helper function to verify github signature
def verify_signature(payload, payload_signature)
    signature = 'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), ENV["WEBHOOK_SECRET"], payload)
    Rack::Utils.secure_compare(signature, payload_signature)
end

def send_telegram_message(text, reply_markup=nil)
    puts "Sending telegram message"
    url = "https://api.telegram.org/bot#{ENV["TELEGRAM_TOKEN"]}/sendMessage?chat_id=#{ENV["TELEGRAM_CHAT_ID"]}&text=#{CGI.escapeURIComponent text}&parse_mode=MarkdownV2"

    if reply_markup != nil
        url += "&reply_markup=#{reply_markup.to_json}"
    end

    puts Net::HTTP::get(URI.parse(url))
end

def send_confirmation_message(commit, url)
    puts "Sending confirmation message"

    telegram_keyboard = {
        "inline_keyboard": [
            [
                {
                    "text": "Deploy",
                    "url": url
                }
            ]
        ]
    }

    lastCommit = commit.last

    commitsWithText = commit.map { |c| "`#{c["id"]}`\n`#{c["message"]}`" }.join("\n\n")

    telegram_text = "🚨 Commit [_#{lastCommit["id"]}_](#{lastCommit["url"]}) has been pushed to the `#{ENV["BRANCH"]}` branch\\.\n\n🚀 The following commits will be deployed\n#{commitsWithText}\n\n\n⬇️ Click the button below to deploy to the *#{ENV["STACK_NAME"]}* stack\\."

    send_telegram_message(telegram_text, telegram_keyboard)
end

def send_deploying_message(commit)
    telegram_text = "🚀 Deploying commit `#{commit}` to the *#{ENV["STACK_NAME"]}* stack\\."

    send_telegram_message(telegram_text)
end

def send_deployed_message(commit)
    telegram_text = "✅ Commit `#{commit}` has been deployed to the **#{ENV["STACK_NAME"]}** stack\\."

    send_telegram_message(telegram_text)
end

get '/' do 200 end

# locks to avoid race conditions
# lock for valid_urls
validURLLock = Mutex.new

# lock for deploy
deployLock = Mutex.new


post '/hook' do
    # check if payload is signed
    github_signature = request.env["HTTP_X_HUB_SIGNATURE_256"]
    if github_signature == nil
        puts "No signature, ignoring"
        return 400
    end

    payload_body = request.body.read
    if verify_signature(payload_body, github_signature) == false
        puts "Invalid signature, ignoring"
        return 400
    end

    # json parse the payload
    payload = ""
    begin
        payload = JSON.parse(params["payload"])
    rescue
        puts "Invalid JSON payload"
        return 400
    end

    # validate payload
    commit = payload["after"]
    if payload["ref"] == nil || commit == nil
        puts "Invalid payload, ignoring"
        return 400
    end

    if payload["ref"] != "refs/heads/#{branch}"
        puts "Not the #{branch} branch, ignoring"
        return 200
    end


    # generate random secure token
    token = SecureRandom.urlsafe_base64(20)

    # get index of url we are going to add
    # and add url to valid_urls
    i = -1
    validURLLock.synchronize do
        i = valid_urls.size
        valid_urls.push "/deploy/#{token}/#{commit}"
    end
    puts "Added /deploy/#{token}/#{commit} to valid_urls"

    send_confirmation_message(payload["commits"], "#{host}/deploy/#{token}/#{commit}")

    # delete url after url_validity seconds
    Thread.new {
        sleep url_validity
        validURLLock.synchronize do
            valid_urls.delete_at i
        end
    }

    200
end

get '/deploy/:token/:commit' do
    # check if url is in valid urls
    # if not, return 404

    if params[:token] == nil || params[:commit] == nil
        return 404
    end

    if not valid_urls.include? "/deploy/#{params[:token]}/#{params[:commit]}"
        return 404
    end

    deployLock.synchronize do
        # delete from valid urls
        # this should be done first
        # as you could accidentally 
        # press the link twice
        # while the deploy is still running
        validURLLock.synchronize do
            valid_urls.delete "/deploy/#{params[:token]}/#{params[:commit]}"
        end

        puts "Deploying #{params[:commit]}"
        send_deploying_message(params[:commit])

        # put deploy script at stack_dir/stack.sh
        `scp -F /dev/null -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i #{ssh_key_path} -P #{ssh_port} ./stack.sh #{ssh_user}@#{ssh_host}:#{stack_dir}/`

        # run deploy script
        `ssh -F /dev/null -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i #{ssh_key_path} -p #{ssh_port} #{ssh_user}@#{ssh_host} 'cd #{stack_dir} && git fetch origin #{branch} && git merge #{params[:commit]} && sh ./stack.sh #{stack_name} up -d | sh'`

        puts "Deployed #{params[:commit]}"
        send_deployed_message(params[:commit])

        200
    end
end

set :port => port
set :bind, "0.0.0.0","[::]"
