module Throttle; module Velocity
  
  class Limiter
    attr_reader :app
    attr_reader :options

    def initialize(app, options = {})
      @app, @options = app, options
    end

    def call(env)
      request = Rack::Request.new(env)
      if request.url.include? "requests/captcha/rate_limit"
        begin
          handle_captcha_post(request)
        rescue => e
          report_failure_to_log(request,e)
          send_captcha_response(true)
        end
      else
        if request_from_mobile?(request)
          ######################################################
          ## ADDING A TEMP HACK TO SUPPORT CURRENT APP RELEASE
          ######################################################
          status = true
          message = nil
          # status,message = valid_mobile_request?(request)
          ######################################################
          status ? app.call(env) : http_error_custom(401,message)
        else
          if(request.env["REQUEST_METHOD"] == "POST")
            allowed?(request) ? app.call(env) : rate_limit_exceeded(request)
          else
            app.call(env)
          end
        end
      end
    end

    def send_captcha_response(flag)
      if flag
        [200, { 'Content-Type' => 'application/json' }, [ { :status => "OK" }.to_json ]]
      else
        [422, { 'Content-Type' => 'application/json' }, [{ :status => 'INVALID_CAPTCHA', :message => 'Captcha validation failed.'}.to_json]]
      end
    end

    protected


    #######################################################
    ## IF call from internal server, bypass Velocity 
    #######################################################  
    def internal_call?(request)
      request.url.include?("internal") ? true : false
    end

    def internal_testing?(request)
      params = request.params
      if params.include?("testing") && params["testing"] == "true"
        return true
      end
      return false
    end

    def rate_limit_exceeded(request)
      report_rate_limit_exceeded(request)
      headers = respond_to?(:retry_after) ? {'Retry-After' => retry_after.to_f.ceil.to_s} : {}
      origin = nil
      origin = request.env['HTTP_ORIGIN'] rescue nil
      headers['Access-Control-Allow-Origin'] = origin if origin
      http_error(options[:code] || 200, options[:message] || 'Caption Required', headers,request)
    end

    def http_error(code, message = nil, headers = {}, request)
      [code, {'Content-Type' => 'application/json'}.merge(headers),[{:captcha_required => true}.to_json]]
    end

    def http_error_custom(code,message = nil,headers = {})
      [code, {'Content-Type' => 'application/json'}.merge(headers),[{:response => message}.to_json]]
    end

    def http_status(code)
      [code, Rack::Utils::HTTP_STATUS_CODES[code]].join(' ')
    end

    #######################################
    # Logging Methods
    #######################################
    def report_rate_limit_exceeded(request)
      unless Dir.exists? "log/velocity"
        Dir.mkdir "log/velocity"
      end
      log_file = Logger.new("log/velocity/limit_exceeded_status_sent.log")
      log_file.error("Limit exceeded status sent for #{request.ip} for url #{request.url}")
    end

    def report_captcha_ans_status(request,flag)
      unless Dir.exists? "log/velocity"
        Dir.mkdir "log/velocity"
      end
      log_file = Logger.new("log/velocity/captcha_ans.log")
      if flag
        log_file.error("Correct answer for throttle captcha post from #{request.ip}")
      else
        log_file.error("Wrong answer for throttle captcha post from #{request.ip}")
      end
    end

    def report_failure_to_log(request,error)
      unless Dir.exists? "log/velocity"
        Dir.mkdir "log/velocity"
      end
      log_file = Logger.new("log/velocity/throttle_errors.log")
      log_file.error("Problem captcha post(handle captcha post code broken) for #{request.ip}")
      log_file.error("Exception : #{error.message}")
    end

    def report_code_broken_in_allowed(request,error)
      unless Dir.exists? "log/velocity"
        Dir.mkdir "log/velocity"
      end
      log_file = Logger.new("log/velocity/allowed_broken.log")
      log_file.error("Allowed Test Code Broken #{request.ip} for #{request.url}")
      log_file.error("Exception : #{error.message}")
    end

  end
end; end
