querystring = require('querystring')
_s = require('underscore.string');

baseUrl = 'https://proapi.whitepages.com/2.0/phone.json'

#
# Request Function -------------------------------------------------------
#

request = (vars) ->

  # Use the API key and Customer ID specified as an environment variables.
  # Assign the values to vars so that we can mask them. This works because the request function is
  # called twice: first to generate the real request, and second to generate the masked request.
  # On the second invocation, the vars properties are already assigned as masked strings.
  # console.log "process.env.WHITEPAGES_API_KEY: #{process.env.WHITEPAGES_API_KEY}"

  vars.api_key ?= process.env.WHITEPAGES_API_KEY ? vars.whitepages.api_key

  url: "#{baseUrl}?api_key=#{vars.api_key}&phone_number=#{vars.lead.phone_1}&response_type=callerid",
  method: 'GET',
  headers:
    Accepts: 'application/json'

request.variables = ->
  [
    { name: 'lead.phone_1', type: 'string', required: true, description: 'Phone number' }
  ]

validate = (vars) ->
  return 'phone must not be blank' unless vars.lead?.phone_1?
  return 'phone must be valid' if vars.lead.phone_1?.valid? and vars.lead.phone_1.valid != true
  return 'phone must not be masked' if vars.lead.phone_1?.masked == true

#
# Response Function ------------------------------------------------------
#

response = (vars, req, res) ->

  result = {}
  
  if res.status == 200
    event = JSON.parse(res.body)
    if event.error 
      result = { outcome: 'error', error: "#{event.error.message}", reason: "#{event.error.message}", billable: 1 }
    else
      if event.messages and event.messages.length
        message_obj = event.messages[0]
        severity = message_obj.severity
        message = message_obj.message.replace /qiWithPhone: /, ""
        code = message_obj.code

        if severity == "warning"
          result = { outcome: 'failure', error: "#{message}", reason: "#{message}", billable: 1 }
        else
          # error
          result = { outcome: 'error', reason: "#{message}", billable: 0 }

      else
        primary_key = event.results[0]
        # console.log 'Primary key is ' + primary_key

        phone_obj = event.dictionary[primary_key]
        phone_number = phone_obj.phone_number
        is_valid = phone_obj.is_valid
        is_connected = phone_obj.is_connected
        line_type = phone_obj.line_type
        carrier = phone_obj.carrier
        is_prepaid = phone_obj.is_prepaid
        reputation_level = phone_obj.reputation.level

        best_location_key = phone_obj.best_location.id.key
        location_obj = event.dictionary[best_location_key]
        address = location_obj.address
        city = location_obj.city
        state = location_obj.state_code
        postal_code = location_obj.postal_code
        lat_long = location_obj.lat_long
        delivery_point = location_obj.delivery_point
        is_receiving_mail = location_obj.is_receiving_mail
        country_code = location_obj.country_code

        # the "belongs to" entity could be a Person, or a Business
        belongs_to_key = phone_obj?.belongs_to?[0].id.key
        belongs_to_obj = event.dictionary[belongs_to_key]
        name = if belongs_to_obj.best_name then belongs_to_obj.best_name else belongs_to_obj.name
        gender = if belongs_to_obj.gender then belongs_to_obj.gender else null
        age_range = if belongs_to_obj.age_range then belongs_to_obj.age_range else null

        result.outcome = 'success'
        result.reason = null
        result.error = null
        result.billable = 1
        result.phone_number = phone_number
        result.country_code = country_code
        result.reputation = { level: reputation_level }
        result.is_connected = is_connected
        result.is_prepaid = is_prepaid
        result.is_valid = is_valid
        result.carrier = carrier
        result.line_type = line_type
        result.belongs_to = {
          name: name
          gender: gender
          age_range: age_range
        }
        result.belongs_to.location = {
          address: address
          city: city
          state: state
          postal_code: postal_code
          delivery_point: delivery_point
          is_receiving_mail: is_receiving_mail
        }
        result.belongs_to.location.lat_long = {
          latitude: lat_long.latitude
          longitude: lat_long.longitude
        }
  else
    # capture the error body, if we have one
    message = res.body
    try 
      json = JSON.parse(res.body)
      message = json.error.message
    catch
      # it's not JSON

    result = { outcome: 'error', reason: "WhitePages error: #{message}", billable: 0 }

  live: result
  
response.variables = ->
  [
    { name: 'live.outcome', type: 'string', description: 'Integration outcome (success, failure, or error)' }
    { name: 'live.reason', type: 'string', description: 'If integration fails, this is the reason why' }
    { name: 'live.phone_number', type: 'string', description: 'Whitepages Pro Phone Number' }
    { name: 'live.is_valid', type: 'boolean', description: 'Whitepages Pro Is Valid' }
    { name: 'live.is_connected', type: 'boolean', description: 'Whitepages Pro Is Connected' }
    { name: 'live.country_code', type: 'string', description: 'Whitepages Pro Country Code' }
    { name: 'live.line_type', type: 'string', description: 'Whitepages Pro Line Type' }
    { name: 'live.carrier', type: 'string', description: 'Whitepages Pro Carrier' }
    { name: 'live.is_prepaid', type: 'boolean', description: 'Whitepages Pro Is Prepaid' }
    { name: 'live.reputation.level', type: 'number', description: 'Whitepages Pro Reputation Level' }
    { name: 'live.error', type: 'string', description: 'Whitepages Pro Error Response' }
  ]


#
# Exports ----------------------------------------------------------------
#

module.exports =
  name: 'Caller ID Data Append'
  validate: validate
  request: request
  response: response

#
# Helpers ----------------------------------------------------------------
#