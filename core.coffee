_ = require 'underscore'
async = require 'async'

exports.respond = (req, res, data, result) ->
  if req.headers.origin
    res.header 'Access-Control-Allow-Origin', req.headers.origin
    res.header 'Access-Control-Allow-Credentials', 'true'
    res.header 'Access-Control-Allow-Headers', 'Authorization'
    res.header 'Access-Control-Allow-Methods', 'POST, GET, OPTIONS, DELETE, PUT'
  res.json data, (result || 200)

verbs = []

exports.verb = (app, route, middleware, callback) ->
  app.post '/' + route, middleware, callback
  verbs.push route

exports.exec = (app, db, getUserFromDbCore, mods) ->

  getUserFromDb = (req, callback) ->
    if req._hasCache
      callback(null, req._cachedUser)
      return
    getUserFromDbCore req, (err, result) ->
      if err
        callback(err)
        return
      req._hasCache = true
      req._cachedUser = result
      callback(null, result)

  def2 = (method, route, preMid, postMid, callback) ->
    func = app[method]
    func.call app, route, preMid, (req, res) ->
      try
        console.log(req.method, req.url)
        callback req, (err, data) ->
          if err
            if err.unauthorized
              res.header 'WWW-Authenticate', 'Basic realm="sally"'
              exports.respond req, res, { err: "unauthed" }, 401
            else
              exports.respond req, res, { err: err.toString() }, 400
            return

          async.reduce postMid, data, (memo, mid, callback) ->
            mid(req, data, callback)
          , (err, result) ->
            if err
              if err.unauthorized
                res.header 'WWW-Authenticate', 'Basic realm="sally"'
                exports.respond req, res, { err: "unauthed" }, 401
              else
                exports.respond req, res, { err: err.toString() }, 400
              return
            exports.respond req, res, result
      catch ex
        console.log(ex.message)
        console.log(ex.stack)
        exports.respond req, res, { err: 'Internal error: ' + ex.toString() }, 500

  fieldFilterMiddleware = (fieldFilter) -> (req, data, callback) ->

    outdata = JSON.parse(JSON.stringify(data))

    if !fieldFilter
      callback(null, data)
      return

    getUserFromDb req, (err, user) ->
      if err
        callback err
        return

      evaledFilter = fieldFilter(user)

      if Array.isArray(outdata)
        outdata.forEach (x) ->
          evaledFilter.forEach (filter) ->
            delete x[filter]
      else
        evaledFilter.forEach (filter) ->
          delete outdata[filter]

      callback(null, outdata)

  validateId = (req, res, next) ->
    if db.isValidId(req.params.id)
      next()
    else
      exports.respond req, res, { err: 'No such id' }, 400 # duplication. can this be extracted out?









  db.getModels().forEach (modelName) ->

    owners = db.getOwners(modelName)
    manyToMany = db.getManyToMany(modelName)

    midFilter = (type) -> (req, res, next) ->
      authFuncs =
        read: mods[modelName].auth || ->
        write: mods[modelName].authWrite
        create: mods[modelName].authCreate
      authFuncs.write ?= authFuncs.read
      authFuncs.create ?= authFuncs.write

      getUserFromDb req, (err, user) ->
        if err
          callback err
          return
        filter = authFuncs[type](user)
        if !filter?
          res.header 'WWW-Authenticate', 'Basic realm="sally"'
          exports.respond req, res, { err: "unauthed" }, 401
        else
          req.queryFilter = filter
          next()

    def2 'get', "/#{modelName}", [midFilter('read')], [fieldFilterMiddleware(mods[modelName].fieldFilter)], (req, callback) ->
      db.list modelName, req.queryFilter, callback

    def2 'get', "/#{modelName}/:id", [validateId, midFilter('read')], [fieldFilterMiddleware(mods[modelName].fieldFilter)], (req, callback) ->
      db.get modelName, req.params.id, req.queryFilter, callback

    def2 'del', "/#{modelName}/:id", [validateId, midFilter('write')], [fieldFilterMiddleware(mods[modelName].fieldFilter)], (req, callback) ->
      db.del modelName, req.params.id, req.queryFilter, callback

    def2 'put', "/#{modelName}/:id", [validateId, midFilter('write')], [fieldFilterMiddleware(mods[modelName].fieldFilter)], (req, callback) ->
      db.put modelName, req.params.id, req.body, req.queryFilter, callback

    def2 'get', "/meta/#{modelName}", [], [], (req, callback) ->
      callback null,
        owns: db.getOwnedModels(modelName).map((x) -> x.name)
        fields:db.getMetaFields(modelName)

    if owners.length == 0
      def2 'post', "/#{modelName}", [midFilter('create')], [fieldFilterMiddleware(mods[modelName].fieldFilter)], (req, callback) ->
        db.post modelName, req.body, callback

    owners.forEach (owner) ->
      def2 'get', "/#{owner.plur}/:id/#{modelName}", [validateId, midFilter('read')], [fieldFilterMiddleware(mods[modelName].fieldFilter)], (req, callback) ->
        db.listSub modelName, owner.sing, req.params.id, req.queryFilter, callback

      def2 'post', "/#{owner.plur}/:id/#{modelName}", [validateId, midFilter('create')], [fieldFilterMiddleware(mods[modelName].fieldFilter)], (req, callback) ->
        db.postSub modelName, req.body, owner.sing, req.params.id, callback

    manyToMany.forEach (many) ->
      def2 'post', "/#{modelName}/:id/#{many.name}/:other", [], [], (req, callback) ->
        db.postMany modelName, req.params.id, many.name, many.ref, req.params.other, callback

      def2 'post', "/#{many.name}/:other/#{modelName}/:id", [], [], (req, callback) ->
        db.postMany modelName, req.params.id, many.name, many.ref, req.params.other, callback

      def2 'get', "/#{modelName}/:id/#{many.name}", [], [], (req, callback) ->
        db.getMany modelName, req.params.id, many.name, callback

      def2 'get', "/#{many.name}/:id/#{modelName}", [], [], (req, callback) ->
        db.getManyBackwards modelName, req.params.id, many.name, callback

      def2 'del', "/#{modelName}/:id/#{many.name}/:other", [], [], (req, callback) ->
        db.get many.ref, req.params.other, (err, data) ->
          db.delMany modelName, req.params.id, many.name, many.ref, req.params.other, (innerErr) ->
            callback(err || innerErr, data)

      def2 'del', "/#{many.name}/:other/#{modelName}/:id", [], [], (req, callback) ->
        db.get modelName, req.params.id, (err, data) ->
          db.delMany modelName, req.params.id, many.name, many.ref, req.params.other, (innerErr) ->
            callback(err || innerErr, data)

  def2 'get', '/', [], [], (req, callback) ->
    callback null,
      roots: db.getModels().filter((name) -> db.getOwners(name).length == 0)
      verbs: verbs

  def2 'options', '*', [], [], (req, callback) ->
    callback null, {}

  def2 'all', '*', [], [], (req, callback) ->
    callback 'No such resource'
