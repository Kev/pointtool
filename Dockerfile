FROM debian
MAINTAINER Kev
VOLUME ["/data"]

RUN apt-get update && apt-get install -y ruby git make ruby-dev libsqlite3-dev sqlite wget
RUN cd / && git clone https://github.com/Kev/pointtool.git && cd /pointtool && gem install bundler && bundle install
RUN gem install passenger
ADD docker-init.sh /
RUN chmod u+rwx /docker-init.sh
RUN passenger start -d || true
RUN passenger stop || true
RUN mkdir -p /data

WORKDIR /
EXPOSE 80
ENTRYPOINT ["/docker-init.sh"]
