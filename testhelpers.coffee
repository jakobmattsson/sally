should = require 'should'
request = require 'request'

defTest = (settings) ->
  obj = {}
  conf = []
  state = {}
  lastRes = null
  lastError = null

  ['post', 'get', 'del', 'put', 'err', 'res'].forEach (method) ->
    obj[method] = (args...) ->
      conf.push { method: method, args: args }
      obj

  rep = (str) ->
    str.replace /#{([0-9a-zA-Z_]*)}/g, (all, exp) ->
      state[exp]

  obj.run = (done) ->

    callb = (item, callback) ->

      if item.method == 'post' || item.method == 'del' || item.method == 'get' || item.method == 'put'
        postData = item.args[1] || {} if item.method == 'post' || item.method == 'put'
        postData = postData.call(state) if typeof postData == 'function'
        finalUrl = settings.origin + rep(item.args[0])

        request {
          url: finalUrl
          method: if item.method == 'del' then 'delete' else item.method
          json: postData
        }, (err, res, body) ->
          parsedBody = if item.method == 'post' || item.method == 'put' then body else JSON.parse body
          if err == null && res.statusCode == 200
            lastRes = parsedBody
            lastError = null
          else
            lastRes = null
            lastError = if err then err else { statusCode: res.statusCode, body: parsedBody }
          callback()

      if item.method == 'res'
        if lastError
          should.fail("Expected an OK, but got error", lastError)
        else
          item.args[1].call(state, lastRes) if item.args[1]
        callback()

      if item.method == 'err'
        if !lastError
          should.fail()
        else
          lastError.statusCode.should.eql item.args[0]
          lastError.body.err.should.eql item.args[1] if item.args.length > 1
        callback()

    conf.forEach (item) ->
      name = "Request method " + item.method.toUpperCase()

      if item.method == 'res'
        name = item.args[0]
      if item.method == 'err'
        name = item.args[0] + ": " + item.args[1]

      it name, (done) -> callb item, done

  obj

exports.query = (title, data) ->
  x = null
  describe title, () ->
    x = defTest data
  x
