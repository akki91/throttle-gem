module Throttle; module Velocity

class Throttle < Limiter
  MOBILE_REQUEST_TIME_THRESHOLD = 300
  SALT = Digest::MD5.hexdigest("some_random_string_here")

  def initialize(app, options = {})
    super
  end

  def allowed?(request)
    begin
      # return true if xbot_pass_in_header(request) #Allow backend Printing(Not more in use)
      return true if internal_call?(request)
      return true unless internal_testing?(request)
      # return true if handle_mobile_api(request)
      config = read_config_file
      config_key = check_if_throttled(request.url,config)
      if config_key
        throttle(request,config,config_key)
      else
        return true
      end
    rescue => e
      report_code_broken_in_allowed(request,e)
      allowed = true
    end
  end

  def request_from_mobile?(request)
    params = request.params
    if params.include?("ts") && params.include?("sp")
      return true
    end
    return false
  end

  def valid_mobile_request?(request)
    return true if internal_call?(request)
    config_key = check_if_throttled(request.url,read_config_file)
    return true unless config_key

    params = request.params
    ts = params["ts"].to_i
    sp = params["sp"]
    if (Time.now.to_i - ts).abs > MOBILE_REQUEST_TIME_THRESHOLD
      return false, "Timestamp Invalid"
    elsif Digest::MD5.hexdigest(SALT+ts.to_s) == sp
      return true
    else
      return false, "Unknown Signing"
    end
  end

  def handle_captcha_post(request)
    unless request.params["response"].nil?
      uri = URI.parse("https://www.google.com/recaptcha/api/siteverify")
      res = Net::HTTP.post_form(uri, {"secret" => "6LdacyITAAAAAGy9AamGla1zRIUBlSMYZ8OmQmJb", "response" => request.params["response"]})
      res = JSON.parse(res.body)
      flag = res["success"] == true ? true : false
      blocked_url = get_blocked_url(request)
      if flag && blocked_url
        # config = read_config_file
        # config_key = check_if_throttled (blocked_url, config) 
        # keys = existing_keys(get_redis_keys(request,config,config_key))
        keys = existing_keys(get_redis_rule_keys_associated_with_blocked_url(request.ip,blocked_url)) 
        ############################
        # LEARNING HERE 
        ############################
        unless keys.nil?
          keys.each do |key|
            # rule_config = config[config_key][get_rule_name_from_key(key)]
            # learning_ratio = rule_config["learning_ratio"]
            learning_ratio = redis_instance.hget(key, "learning_ratio").to_f
            # learning_cap = rule_config["learning_cap"].to_i
            learning_cap = redis_instance.hget(key, "learning_cap").to_i
            max_count = redis_instance.hget(key, "max_count").to_i
            max_count = (max_count * learning_ratio).to_i
            max_count = learning_cap if max_count > learning_cap
            redis_instance.hmset(key, "current_count",0, "start_time",request_time, "max_count", max_count)
          end
        end
        whitelist_client(request.ip)
      end
    else
      flag = false
    end
    report_captcha_ans_status(request,flag)
    send_captcha_response(flag)
  end

  def get_redis_rule_keys_associated_with_blocked_url(ip, blocked_url)
    all_rule_keys_for_ip = redis_instance.smembers(ip)
    key_url_part = all_rule_keys_for_ip.map{|k| k.split(":")[1]}.uniq
    associated_url = key_url_part.select{|k| blocked_url.include? k}
    associated_rules = all_rule_keys_for_ip.select{|k| k.include? associated_url[0]}
  end
  
  def check_if_throttled(request_url,config)
    ###############################
    # Handle captcha GET, dont' trust rules
    ###############################    
    return false if request_url.include? "captcha" 
    ###############################
    config.keys.each do |path|
      if request_url.include? path
        return path 
      end
    end
    return false
  end

  def map_key_to_ip(key,ip)
    redis_instance.sadd(ip,key)
  end

  def key_exists(key)
    redis_instance.exists(key)
  end

  def read_redis(key)
    hash = redis_instance.hgetall(key)
  end

  def throttle(request, config, config_key)
    keys = get_redis_keys(request,config,config_key)
    initialize_keys(non_existing_keys(keys),config,config_key,request.ip)
    return false if client_greylisted? request
    url_config = config[config_key]
    is_request_allowed(request,existing_keys(keys),url_config)
  end

  def client_greylisted? request
    return key_exists(greylist_key(request.ip))
  end

  def get_rule_name_from_key(key)
    key.split(/:/).last
  end

  def is_request_allowed(request, keys, url_config)
    allowed = true
    keys.each do |key|
      redis_hash = read_redis(key)
      if request_time - redis_hash["start_time"].to_i < url_config[get_rule_name_from_key(key)]["time"].to_i
        if redis_hash["current_count"].to_i < redis_hash["max_count"].to_i
          update_count(key)
        else
          greylist_client(request)
          return false
        end
      elsif
        reinitiate_count(key)
      end
    end 
    return allowed
  end

  def greylist_client(request)#### should come with an expiry?
    redis_instance.set(greylist_key(request.ip), request.url)
  end

  def get_blocked_url(request)
    redis_instance.get(greylist_key(request.ip))
  end

  def initialize_keys(keys, config, config_key, ip)
    keys.each do |key|
      rule_name = key.split(/:/).last
      max_count = config[config_key][rule_name]["count"]
      learning_ratio = config[config_key][rule_name]["learning_ratio"]
      learning_cap = config[config_key][rule_name]["learning_cap"]
      redis_instance.hmset(key, "current_count",0, "max_count",max_count, "start_time",request_time, "learning_ratio",learning_ratio ,"learning_cap",learning_cap)
      map_key_to_ip(key,ip)
    end
  end

  def existing_keys(keys)
    keys.each.map{|key| key if key_exists(key)}.compact
  end

  def non_existing_keys(keys)
    keys.each.map{|key| key if !key_exists(key)}.compact
  end

  def update_count(key)
    redis_instance.hincrby(key,"current_count",1)
  end

  def reinitiate_count(key)
    redis_instance.hmset(key,"current_count",1, "start_time",request_time)
  end

  def get_redis_keys(request, config, config_key)
    key_prefix = request_identifier(request)
    key_prefix += ":#{config_key}"
    keys = config[config_key].keys.map{|k| key_prefix + ":#{k}"}
    return keys
  end

  def initialize_client(key, config, config_key)
    max_count = config[config_key]["count"]
    redis_instance.hmset(key, "current_count",0, "max_count",max_count, "start_time",request_time, "blocked","false")
  end

  def request_identifier(request)
    ####################################
    # Conside session id as well
    ####################################
    # hack_request_env(request)
    # session = request.env["rack.request.cookie_hash"][Rails.application.config.session_options[:key]] rescue false
    # key += ":#{session}" if session
    request.ip
  end

  def redis_instance
    Throttle_redis
  end

  def read_config_file
    YAML.load_file('config/throttle.yml')
  end

  def request_time
    Time.now.to_i ### OR request time?
  end

  def greylist_key(ip)
    return "greylist:" + ip
  end

  ################################################
  #Methods to implement Grey => white and learning
  ################################################
  def whitelist_client(ip)
    redis_instance.del(greylist_key(ip))
  end

end

end; end
