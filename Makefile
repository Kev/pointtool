.PHONY: all
all: build

build:
	docker build -t pointtool .

test: destroy build
	mkdir -p data
	docker run -d -p 1081:80 -v `pwd`/data:/data --name pointtool pointtool

log:
	docker logs -f pointtool

enter:
	docker exec -it pointtool /bin/bash

destroy:
	docker stop pointtool || true
	docker rm --volumes pointtool || true
