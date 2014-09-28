Point Tool
============

Eve Online contribution tracking tool

Copy config.yml.sample to config.yml, and edit as appropriate.

To run, make sure you have bundler installed (`gem install bundler`), `bundle install` and then `ruby main.rb`.


## Docker
To generate a docker image, run `docker build -t yourname/pointtool .`. When executed the image will expose itself on port 80, so something like `docker run --name pointtool -e POINTTOOL_BASE_URL='' -e POINTTOOL_CORP_NAME='My Corp' -p 2080:80 yourname/pointtool` is appropriate to get you running. Look at docker-init.sh to see which environment variables you'll need to set
