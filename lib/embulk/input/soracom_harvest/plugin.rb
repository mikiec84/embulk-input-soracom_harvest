module Embulk
  module Input
    module SoracomHarvest
      class Plugin < InputPlugin
        ::Embulk::Plugin.register_input('soracom_harvest', self)

        PREVIEW_COUNT = 15
        END_POINT_URL_DEFAULT = 'https://api.soracom.io/v1'
        TAG_VALUE_MATCH_MODE_DEFAULT = 'exact'
        RETRY_LIMIT_DEFAULT = 5
        RETRY_INITIAL_WAIT_SEC_DEFAULT = 2

        attr_reader :start_datetime
        attr_reader :end_datetime
        attr_reader :last_record # TODO
        attr_reader :filter

        def self.transaction(config, &control)
          # configuration code:
          task = {
            'auth_key' => config.param('auth_key', :string),
            'auth_key_id' => config.param('auth_key_id', :string),
            'target' => config.param('target', :string, default: 'harvest'),
            # TODO
            'incremental' => config.param('incremental', :bool, default: false),
            'start_datetime' => config.param('start_datetime', :string, default: nil),
            'end_datetime' => config.param('end_datetime', :string, default: nil),
            #'last_record' => config.param("last_record", :string, default: nil),
            'endpoint' => config.param('endpoint', :string, default: END_POINT_URL_DEFAULT),
            'filter' => config.param('filter', :string, default: nil),
            'tag_value_match_mode' => config.param('tag_value_match_mode', :string, default: TAG_VALUE_MATCH_MODE_DEFAULT),
            'retry_limit' => config.param('retry_limit', :integer, default: RETRY_LIMIT_DEFAULT),
            'retry_initial_wait_sec' => config.param('retry_initial_wait_sec', :integer, default: RETRY_INITIAL_WAIT_SEC_DEFAULT),
            'columns' => config.param('columns', :array),
          }

          columns = embulk_columns(config)

          resume(task, columns, 1, &control)
        end

        def self.resume(task, columns, count, &control)
          task_reports = yield(task, columns, count)

          next_config_diff = task_reports.first
          return next_config_diff
        end

        def init
          if task['start_datetime']
            raise ConfigError.new "'start_datetime' can't be used when 'target: sims'" if task['target'] == 'sims'
            @start_datetime = convert_to_unixtimestamp(task['start_datetime'])
          end

          if task['end_datetime']
            raise ConfigError.new "'end_datetime' can't be used when 'target: sims'" if task['target'] == 'sims'
            @end_datetime = convert_to_unixtimestamp(task['end_datetime'])
          end

          # if task['last_record']
          #   @last_record = convert_to_unixtimestamp(task['last_record'])
          # end

          @filter = to_hash(task['filter'])
        end

        def self.guess(config)
          auth_key_id = config.param(:auth_key_id, :string)
          auth_key = config.param(:auth_key, :string)
          target = config.param(:target, :string)
          tag_value_match_mode = config.param(:tag_value_match_mode, :string, default: TAG_VALUE_MATCH_MODE_DEFAULT)

          retry_limit = config.param(:retry_limit, :integer, default: RETRY_LIMIT_DEFAULT)
          retry_initial_wait_sec = config.param(:retry_initial_wait_sec, :integer, default: RETRY_INITIAL_WAIT_SEC_DEFAULT)

          options = {
            endpoint: config.param(:endpoint, :string, default:END_POINT_URL_DEFAULT),
            retry_limit: retry_limit,
            retry_initial_wait_sec: retry_initial_wait_sec,
          }
          client = SoracomClient.new(auth_key_id, auth_key, options)

          # TODO last_record
          sims = client.list_subscribers(filter: @filter, limit: 1, last_record: nil, tag_value_match_mode: tag_value_match_mode)
          raise ConfigError.new "Failed to guess. No registered SIM found" if sims.size == 0

          Embulk::logger.info "Getting schema for target: '#{target}'"
          if target == 'sims'
            columns = self.get_sim_schema(sims.first)
          else
            records = client.list_subscribers_imsi_data(imsi: sims.first['imsi'], from: @start_datetime, to: @end_datetime, limit: 1)
            raise ConfigError.new "Failed to guess. No records found at SORACOM Harvest" if records.size == 0
            columns = self.get_harvest_schema(records.first)
          end

          {
            'columns' => columns
          }
        end

        def run
          client = SoracomClient.new(task['auth_key_id'], task['auth_key'], get_request_options(task))

          # TODO last_record
          sims = client.list_subscribers(filter: @filter, last_record: nil, tag_value_match_mode: task['tag_value_match_mode'])

          if sims.size > 0
            columns = task['columns']

            counter = 0
            last_record = nil
            sims.each do |sim|
              if task['target'] == 'sims'
                page_builder.add(format_record(sim, columns, false))
              else
                # TODO last_record
                records = client.list_subscribers_imsi_data(imsi: sim['imsi'], from: @start_datetime, to: @end_datetime, last_record: @last_record)
                if records.size > 0
                  records.each do |record|
                    page_builder.add(format_record(record, columns, true))
                    last_record = record['time']
                  end
                end
              end
              break if preview? && (counter += 1) >= PREVIEW_COUNT
            end
          end

          page_builder.finish

          return {} unless task[:incremental]

          task_report = {
            last_record: convert_unixtime_to_date(last_record)
          }
        end

        def self.get_sim_schema(sim)
          columns = []
          sim.each do |k, v|
            type =
              case k
                when 'plan'
                  'long'
                when 'createdAt', 'lastModifiedAt', 'expiredAt', 'expiryTime', 'createdTime', 'lastModifiedTime'
                  'timestamp'
                when 'imeiLock', 'terminationEnabled'
                  'boolean'
                when 'tags', 'sessionStatus'
                  'json'
                else
                  'string'
              end
            columns << {name: k, type: type}
          end
          columns
        end

        def self.get_harvest_schema(record)
          content_type = record['contentType']
          type = content_type == 'application/json' ? 'json' : 'string'
          [
            {name: 'content', type: type},
            {name: 'contentType', type: 'string'},
            {name: 'time', type: 'timestamp'},
          ]
        end

        def format_record(record, columns, is_harvest)
          values = columns.map do |column|
            name = column['name'].to_s
            value = record[name]
            cast_value(column, value, is_harvest)
          end
        end

        def cast_value(column, value, is_harvest)
          return if value.to_s.empty? # nil or empty string

          case column['type'].to_s
            when 'timestamp'
              begin
                Time.at(value / 1000.0).round(3)
              rescue
                raise DataError.new "Can't parse as Time '#{value}' (column is #{column['name']})"
              end
            when 'json'
              if is_harvest
                begin
                  JSON.parse(value)
                rescue
                  raise DataError.new "Can't parse as JSON '#{value}' (column is #{column['name']})"
                end
              else
                value.to_json
              end
            else
              value
          end
        end

        def preview?
          begin
            # http://www.embulk.org/docs/release/release-0.6.12.html
            org.embulk.spi.Exec.isPreview()
          rescue java.lang.NullPointerException => e
            false
          end
        end

        def self.embulk_columns(config)
          config.param(:columns, :array).map do |column|
            name = column['name']
            type = column['type'].to_sym

            Column.new(nil, name, type, column['format'])
          end
        end

        def get_request_options(task)
          {
            endpoint: task[:endpoint],
            retry_limit: task[:retry_limit],
            retry_initial_wait_sec: task[:retry_initial_wait_sec],
          }
        end

        def to_hash(str)
          return nil if str.nil?
          array = str.delete(' ').split(/[:,]/)
          array.each_slice(2).map {|k, v| [k.to_sym, v] }.to_h
        end

        def convert_unixtime_to_date(unixtime)
          return nil if unixtime.nil?
          Time.at(unixtime / 1000.0).strftime('%Y-%m-%d %H:%M:%S.%3N %z')
        end

        def convert_to_unixtimestamp(time)
          begin
            v = Time.parse(time)
            v.to_i * 1000 + v.usec/1000
          rescue
            raise ConfigError.new "Failed to convert ['#{time}'] to UNIX timestamp"
          end
        end
      end
    end
  end
end
