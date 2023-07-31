FROM ruby:alpine

RUN apk add --update --no-cache \
    build-base \
    openssh

# clean up
RUN rm -rf /var/cache/apk/*

WORKDIR /app

COPY Gemfile* /app/
RUN gem install bundler
RUN bundle

COPY . /app

ENV APP_ENV=production

CMD ["ruby", "stackhook.rb"]
