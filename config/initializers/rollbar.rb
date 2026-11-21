Rollbar.configure do |config|
  # Without configuration, Rollbar is enabled in all environments.
  # To disable in specific environments, set config.enabled=false.

  config.access_token = ENV["ROLLBAR_ACCESS_TOKEN"]
  config.enabled = ENV["ROLLBAR_ACCESS_TOKEN"].present?

  # Here we'll disable in 'test':
  if Rails.env.test?
    config.enabled = false
  end

  # Reports carry technical data only: the values of parameters, request bodies, cookies, session and
  # job data are scrubbed, the IP address and the signed-in user are left out. The request id of a
  # report finds the request in our own logs.
  config.scrub_fields = :scrub_all
  config.scrub_whitelist = %i[controller action job job_id]
  config.scrub_headers |= [ "Referer" ]
  config.collect_user_ip = false
  # The person is dropped from the built report. Setting person_id_method to nil instead makes Rollbar
  # fail on every report of a request (Rollbar::Item#ignored? calls to_sym on it).
  config.transform << ->(options) { options[:payload]["data"].delete(:person) }

  # Requests for pages that do not exist come almost only from scanners, and reporting them used up the
  # rate limit of the project. They are still logged as 404.
  config.exception_level_filters.merge!("ActionController::RoutingError" => "ignore")

  # If you want to attach custom data to all exception and message reports,
  # provide a lambda like the following. It should return a hash.
  # config.custom_data_method = lambda { {:some_key => "some_value" } }

  # Add exception class names to the exception_level_filters hash to
  # change the level that exception is reported at. Note that if an exception
  # has already been reported and logged the level will need to be changed
  # via the rollbar interface.
  # Valid levels: 'critical', 'error', 'warning', 'info', 'debug', 'ignore'
  # 'ignore' will cause the exception to not be reported at all.
  # config.exception_level_filters.merge!('MyCriticalException' => 'critical')
  #
  # You can also specify a callable, which will be called with the exception instance.
  # config.exception_level_filters.merge!('MyCriticalException' => lambda { |e| 'critical' })

  # Enable asynchronous reporting (uses girl_friday or Threading if girl_friday
  # is not installed)
  # config.use_async = true
  # Supply your own async handler:
  # config.async_handler = Proc.new { |payload|
  #  Thread.new { Rollbar.process_from_async_handler(payload) }
  # }

  # Enable asynchronous reporting (using sucker_punch)
  # config.use_sucker_punch

  # Enable delayed reporting (using Sidekiq)
  # config.use_sidekiq
  # You can supply custom Sidekiq options:
  # config.use_sidekiq 'queue' => 'default'

  # If your application runs behind a proxy server, you can set proxy parameters here.
  # If https_proxy is set in your environment, that will be used. Settings here have precedence.
  # The :host key is mandatory and must include the URL scheme (e.g. 'http://'), all other fields
  # are optional.
  #
  # config.proxy = {
  #   host: 'http://some.proxy.server',
  #   port: 80,
  #   user: 'username_if_auth_required',
  #   password: 'password_if_auth_required'
  # }

  # If you run your staging application instance in production environment then
  # you'll want to override the environment reported by `Rails.env` with an
  # environment variable like this: `ROLLBAR_ENV=staging`. This is a recommended
  # setup for Heroku. See:
  # https://devcenter.heroku.com/articles/deploying-to-a-custom-rails-environment
  config.environment = ENV["ROLLBAR_ENV"].presence || Rails.env
end
