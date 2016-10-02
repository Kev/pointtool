FROM debian:8
MAINTAINER Kev
VOLUME ["/data"]

RUN apt-get update && apt-get install -y ruby make ruby-dev libsqlite3-dev sqlite wget build-essential
RUN mkdir /pointtool
RUN gem install bundler
ADD Gemfile Gemfile.lock /pointtool/
RUN cd /pointtool && bundle install
ADD docker-init.sh /
ADD . /pointtool
RUN chmod u+rwx /docker-init.sh
RUN passenger start -d || true
RUN passenger stop || true
RUN mkdir -p /data

WORKDIR /
EXPOSE 80
ENTRYPOINT ["/docker-init.sh"]
