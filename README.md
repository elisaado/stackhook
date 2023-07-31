# stackhook
Deploy docker compose "stacks" with ease.

Stackhook lets you know whenever there is a new push to the GitHub repository of your stack, and lets you deploy it instatly.

## Why

I was getting tired of ssh'ing into my server all the time, just to run

```bash
cd stack
git pull
docker-compose up
```

## How

First you set up the stack on your server, making sure you are fully authenticated on git, with ssh keys to pull.

Then
1. decide on a domain
2. set up a webhook on GitHub
3. register a bot on telegram and get its token
4. generate a secret for the webhook and fill it in on GitHub.
5. copy the `.env.example` to a `.env` and fill in the values
6. deploy this app!

## Deployment example
To deploy the app, you can build the image yourself using

```bash
docker build -t stackhook stackhook
```

(notinng that the stackhook repository is located at `./stackhook`)

Then, from wherever your `.env` is located, you can do

```bash
docker run --env-file .env -p 9999:9999 -v "/home/stack/.ssh/id_ed25519:/app/ssh_key" -d stackhook
```
