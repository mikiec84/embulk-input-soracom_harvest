require 'perfect_retry'
require 'httpclient'

# SORACOM Ruby SDK doesn't support SORACOM Harvest for now(Dec 2016).
# So I send HTTP request to API directly.
# Want to remove this Class in the future when Ruby SDK supports Harvest.

module Embulk
  module Input
    module SoracomHarvest
      class SoracomClient
        attr_reader :auth_key_id
        attr_reader :auth_key
        attr_reader :options

        attr_reader :client

        attr_reader :api_key
        attr_reader :token

        def initialize(auth_key_id, auth_key, options)
          @auth_key_id = auth_key_id
          @auth_key = auth_key
          @options = options
          auth
        end

        def auth
          @client = HTTPClient.new
          postdata = {'authKeyId' => auth_key_id, 'authKey' => auth_key}
          header = {'Content-Type' => 'application/json'}

          response = get(path: '/auth', header: header, postdata: postdata)

          @api_key = response['apiKey']
          @token = response['token']
        end

        def list_subscribers(filter: {}, limit: 10000, last_record: nil, tag_value_match_mode: nil)
          query = {
            'limit' => limit
          }
          query['last_evaluated_key'] = last_record unless last_record.nil?

          if filter.nil?
            path = '/subscribers'
          else
            key = filter.keys.first.to_s
            value = filter.values.first
            Embulk.logger.info "Requesting with filter '#{key}: #{value}'"
            case key
              when 'imsi'
                path = "/subscribers/#{value}"
              when 'msisdn'
                path = "/subscribers/msisdn/#{value}"
              when 'status'
                path = '/subscribers'
                query['status_filter'] = value
              when 'speed_class'
                path = '/subscribers'
                query['speed_class_filter'] = value
              else
                path = '/subscribers'
                query['tag_name'] = key
                query['tag_value'] = value
                query['tag_value_match_mode'] = tag_value_match_mode unless tag_value_match_mode.nil?
            end
          end

          response = get(path: path, query: query)
          Embulk.logger.info "#{response.size} SIMs found"

          response
        end

        def list_subscribers_imsi_data(imsi: nil, from: nil, to: nil, limit: 100000, last_record: nil)
          path = "/subscribers/#{imsi}/data"
          query = {
            'sort' => 'asc',
            'limit' => limit,
          }
          query['from'] = from unless from.nil?
          query['to'] = to unless to.nil?
          query['last_evaluated_key'] = last_record unless last_record.nil?
          response = get(path: path, query: query)
          Embulk.logger.info "#{response.size} records found at Soracom Harvest for SIM: #{imsi}"

          response
        end

        def get(path: nil, header: {}, query: nil, postdata: nil)
          header = header.merge(
            'X-Soracom-API-Key' => @api_key,
            'X-Soracom-Token' => @token,
            'Accept' => 'application/json',
          ) unless path == '/auth'

          retryer.with_retry do
            url = @options[:endpoint] + path

            if postdata
              response = @client.post(url, postdata.to_json, header)
            else
              response = @client.get(url, query, header)
            end

            Embulk::logger.debug "url: #{url}"
            Embulk::logger.debug "Query: #{query}"
            Embulk::logger.debug "POST data: #{postdata}"
            Embulk::logger.debug "Status code: #{response.code}"
            Embulk::logger.debug "Response body: #{response.body}"

            handle_error(response)

            response_body = JSON.parse(response.body)
            if path == '/auth' || response_body.is_a?(Array)
              body = response_body
            else
              body = Array[response_body]
            end

            body
          end
        end

        def handle_error(response)
          code = response.code

          case code
            when 400..499
              message = "StatusCode: #{code}"

              body = nil
              begin
                body = JSON.parse(response.body)
              rescue
                message << ": #{response.body}"
                raise ConfigError.new message
              end

              if body.is_a?(Array)
                body = body.first
              end
              message << ", ErrorCode: #{body['code']}" if body["code"]
              message << ", Message: #{body['message']}" if body["message"]
              case body["code"]
                # TODO
                when "INVALID_QUERY_LOCATOR", "QUERY_TIMEOUT"
                  # will be retried
                  raise message
                else
                  # won't retry
                  raise ConfigError.new message
              end
            when 500..599
              raise "SORACOM API returns StatusCode: #{code}. Retrying..."
          end
        end

        def retryer
          PerfectRetry.new do |config|
            config.limit = options[:retry_limit]
            config.logger = Embulk.logger
            config.log_level = nil

            # TODO
            #config.rescues = Google::Apis::Core::HttpCommand::RETRIABLE_ERRORS
            config.dont_rescues = [Embulk::DataError, Embulk::ConfigError]
            config.sleep = lambda{|n| options[:retry_initial_wait_sec]* (2 ** (n-1)) }
            config.raise_original_error = true
          end
        end
      end
    end
  end
end
