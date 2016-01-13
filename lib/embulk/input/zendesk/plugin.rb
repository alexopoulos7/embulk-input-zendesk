require "perfect_retry"

module Embulk
  module Input
    module Zendesk
      class Plugin < InputPlugin
        ::Embulk::Plugin.register_input("zendesk", self)

        def self.transaction(config, &control)
          task = {
            login_url: config.param("login_url", :string),
            auth_method: config.param("auth_method", :string, default: "basic"),
            username: config.param("username", :string, default: nil),
            password: config.param("password", :string, default: nil),
            token: config.param("token", :string, default: nil),
            access_token: config.param("access_token", :string, default: nil),
            retry_limit: config.param("retry_limit", :integer, default: 5),
            retry_wait_initial_sec: config.param("retry_wait_initial_sec", :integer, default: 1),
            schema: config.param(:columns, :array),
          }
          unless enough_credentials?(task)
            raise Embulk::ConfigError.new("Missing required credentials for #{task[:auth_method]}")
          end

          columns = task[:schema].map do |column|
            name = column["name"]
            type = column["type"].to_sym

            Column.new(nil, name, type, column["format"])
          end

          resume(task, columns, 1, &control)
        end

        def self.resume(task, columns, count, &control)
          task_reports = yield(task, columns, count)

          next_config_diff = {}
          return next_config_diff
        end

        def self.enough_credentials?(task)
          case task[:auth_method]
          when "basic"
            task[:username] && task[:password]
          when "token"
            task[:username] && task[:token]
          when "oauth"
            task[:access_token]
          else
            raise Embulk::ConfigError.new("Unknown auth_method (#{task[:auth_method]}). Should pick one from 'basic', 'token' or 'oauth'.")
          end
        end

        # TODO
        #def self.guess(config)
        #  sample_records = [
        #    {"example"=>"a", "column"=>1, "value"=>0.1},
        #    {"example"=>"a", "column"=>2, "value"=>0.2},
        #  ]
        #  columns = Guess::SchemaGuess.from_hash_records(sample_records)
        #  return {"columns" => columns}
        #end

        def init
        end

        def run
          client = Client.new(task[:credentials], retryer)
          method = preview? ? :tickets : :ticket_all
          client.send(method) do |ticket|
            values = extract_values(ticket)
            page_builder.add(values)
          end

          page_builder.finish

          task_report = {}
          return task_report
        end

        def preview?
          org.embulk.spi.Exec.isPreview()
        rescue java.lang.NullPointerException => e
          false
        end

        def retryer
          PerfectRetry.new do |config|
            config.limit = task[:retry_limit]
            config.logger = Embulk.logger
            config.log_level = nil
            config.dont_rescues = [Embulk::DataError, Embulk::ConfigError]
            config.sleep = lambda{|n| task[:retry_wait_initial_sec]* (2 ** (n-1)) }
          end
        end

        def extract_values(ticket)
          values = task[:schema].map do |column|
            ticket[column["name"].to_s]
          end

          values
        end
      end

    end
  end
end
