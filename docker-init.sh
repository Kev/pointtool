#!/bin/sh
echo "base_url: '$POINTTOOL_BASE_URL'" > /pointtool/config.yml
echo "corp_name: '$POINTTOOL_CORP_NAME'" >> /pointtool/config.yml
echo "trusted_url_base: '$POINTTOOL_TRUSTED_URL_BASE'" >> /pointtool/config.yml
echo "dev_mode: false" >> /pointtool/config.yml
echo "fake_igb_character: ''" >> /pointtool/config.yml
echo "sha_salt: '$POINTTOOL_SHA_SALT'" >> /pointtool/config.yml
echo "cookie_secret: '$POINTTOOL_COOKIE_SECRET'" >> /pointtool/config.yml
echo "db_path: '/data/points.db'"
cd /pointtool
# Want to do this, but haven't worked it out yet.
# passenger start --port 80 -e production
# So instead just run the built-in webrick
rackup -p 80
