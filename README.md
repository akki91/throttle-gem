# Server Integration

### Installation

Add this line to your application's Gemfile:

    gem 'velocity'

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install velocity

### Usage

1. config/throttle.yml to be added in rails Repo, containing the rules for throttling.
3. In application.rb, require 'throttle/velocity' and add config.middleware.use Throttle::Velocity::Throttle.
# Clients Integration


## Native Apps

Along with every POST request, two parameters are to be sent in query params.

 Expected Inputs - compulsory
- ts : Value of ts to be set with current timestamp, available from backend server (to be fetched before every POST)

  Expected Inputs
  - Nothing

  Expected Output
  - current_timestamp: #{time}
- sp : Digest::MD5.hexdigest(SALT+ts.to_s): (sign param), SALT is available at production servers only

Expected Output

If everything works fine, you will get expected response from the API being called. Otherwise you will get following messages(these messages should be logged from App) in response key with 200 HTTP response.
- "Timestamp Invalid" (when ts validations fails)
- "Unknown Signing" (when sp validation fails)

*These two error conditions should be checked while developing(by sending wrong ts/sp).*

## Web
Expected Inputs

- None

Expected Outputs

For any POST request, if limit is exceeded

- HTTP status: 200, Response JSON: { captcha_required: true}


Expected Input

  - Nothing

Expected Output

  - Google Captcha/ Or you also use in house captcha image

Captcha is to be posted at 

API: https://your-service.com/api/requests/captcha/rate_limit

Compulsory Input: captcha_text

Expected Output:
- HTTP : 200, :status => "OK"
- HTTP : 200, :status => 'INVALID_CAPTCHA', :message => 'Captcha validation failed.'

In Your Service where this gem is used, 3 things needs to be done
 - Redis Namespace Initilization ()
 - Use this middleware in application.rb (https://github.com/akki91/Sample-Config/blob/master/appliation.rb)
 - create config/throttle.yml with rules (https://github.com/akki91/Sample-Config/blob/master/throttle.yml.sample)
