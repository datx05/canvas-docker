FROM instructure/ruby-passenger:2.4

ENV APP_HOME /usr/src/app/
ENV RAILS_ENV "development"
ENV NGINX_MAX_UPLOAD_SIZE 10g
ENV YARN_VERSION 1.12.3-1

# Work around github.com/zertosh/v8-compile-cache/issues/2
# This can be removed once yarn pushes a release including the fixed version
# of v8-compile-cache.
ENV DISABLE_V8_COMPILE_CACHE 1

USER root
WORKDIR /root
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash - \
  && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
  && printf 'path-exclude /usr/share/doc/*\npath-exclude /usr/share/man/*' > /etc/dpkg/dpkg.cfg.d/01_nodoc \
  && echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && curl -sS https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
  && apt-get update -qq \
  && apt-get install -qqy --no-install-recommends \
       nodejs \
       yarn="$YARN_VERSION" \
       libxmlsec1-dev \
       python-lxml \
       libicu-dev \
       postgresql-9.5 \
       unzip \
       fontforge \
       supervisor \
       redis-server \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /home/docker/.gem/ruby/$RUBY_MAJOR.0

RUN if [ -e /var/lib/gems/$RUBY_MAJOR.0/gems/bundler-* ]; then BUNDLER_INSTALL="-i /var/lib/gems/$RUBY_MAJOR.0"; fi \
  && gem uninstall --all --ignore-dependencies --force $BUNDLER_INSTALL bundler \
  && gem install bundler --no-document -v 1.16.1 \
  && find $GEM_HOME ! -user docker | xargs chown docker:docker

COPY assets/dbinit.sh ${APP_HOME}dbinit.sh
COPY assets/start.sh ${APP_HOME}start.sh
RUN chmod 755 ${APP_HOME}*.sh

COPY assets/supervisord.conf /etc/supervisor/supervisord.conf
COPY assets/pg_hba.conf /etc/postgresql/9.5/main/pg_hba.conf
RUN sed -i "/^#listen_addresses/i listen_addresses='*'" /etc/postgresql/9.5/main/postgresql.conf

RUN cd ${APP_HOME} \
    && git clone --depth=1 https://github.com/instructure/canvas-lms.git -b stable

WORKDIR ${APP_HOME}canvas-lms

COPY assets/database.yml config/database.yml
COPY assets/redis.yml config/redis.yml
COPY assets/cache_store.yml config/cache_store.yml
COPY assets/development-local.rb config/environments/development-local.rb
COPY assets/outgoing_mail.yml config/outgoing_mail.yml

RUN for config in amazon_s3 delayed_jobs domain file_store security external_migration \
       ; do cp config/$config.yml.example config/$config.yml \
       ; done

RUN $GEM_HOME/bin/bundle install --jobs 8 --without="mysql" \
  && yarn install --pure-lockfile

RUN COMPILE_ASSETS_NPM_INSTALL=0 $GEM_HOME/bin/bundle exec rake canvas:compile_assets_dev

RUN mkdir -p .yardoc \
             app/stylesheets/brandable_css_brands \
             app/views/info \
             client_apps/canvas_quizzes/dist \
             client_apps/canvas_quizzes/node_modules \
             client_apps/canvas_quizzes/tmp \
             config/locales/generated \
             gems/canvas_i18nliner/node_modules \
             gems/selinimum/node_modules \
             log \
             node_modules \
             packages/canvas-planner/lib \
             packages/canvas-planner/node_modules \
             pacts \
             public/dist \
             public/doc/api \
             public/javascripts/client_apps \
             public/javascripts/compiled \
             public/javascripts/translations \
             reports \
             tmp \
             /home/docker/.bundler/ \
             /home/docker/.cache/yarn \
             /home/docker/.gem/ \
  && find ${APP_HOME} /home/docker ! -user docker -print0 | xargs -0 chown -h docker:docker

ENV CANVAS_LMS_ADMIN_EMAIL "canvas@example.edu"
ENV CANVAS_LMS_ADMIN_PASSWORD "canvas-docker"
ENV CANVAS_LMS_ACCOUNT_NAME "Canvas Docker"
ENV CANVAS_LMS_STATS_COLLECTION "opt_out"

RUN service postgresql start && sleep 5 \
    && sudo -u postgres /usr/lib/postgresql/9.5/bin/createuser --superuser canvas \
    && sudo -u postgres /usr/lib/postgresql/9.5/bin/createdb -E UTF-8 -T template0 --lc-collate=en_US.UTF-8 --lc-ctype=en_US.UTF-8 --owner canvas canvas_$RAILS_ENV \
    && sudo -u postgres /usr/lib/postgresql/9.5/bin/createdb -E UTF-8 -T template0 --lc-collate=en_US.UTF-8 --lc-ctype=en_US.UTF-8 --owner canvas canvas_queue_$RAILS_ENV \
    && cd ${APP_HOME}canvas-lms \
    && $GEM_HOME/bin/bundle exec rake db:initial_setup \
    && psql -U canvas -d canvas_development -c "INSERT INTO developer_keys (api_key, email, name, redirect_uri) VALUES ('test_developer_key', 'canvas@example.edu', 'Canvas Docker', 'http://localhost:8000');" \
    && psql -U canvas -d canvas_development -c "INSERT INTO access_tokens (created_at, crypted_token, developer_key_id, purpose, token_hint, updated_at, user_id) SELECT now(), '4bb5b288bb301d3d4a691ebff686fc67ad49daa8', dk.id, 'canvas-docker', '', now(), 1 FROM developer_keys dk where dk.email = 'canvas@example.edu';"

# postgres
EXPOSE 5432
# redis
EXPOSE 6379
# canvas
EXPOSE 3000

CMD ["sh", "-c", "cd $APP_HOME && ./start.sh"]
