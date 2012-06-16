_ = require 'underscore'

exports.respond = (req, res, data, result) ->
  res.header 'Access-Control-Allow-Origin', req.headers.origin
  res.header 'Access-Control-Allow-Credentials', 'true'
  res.header 'Access-Control-Allow-Headers', 'Authorization'
  res.header 'Access-Control-Allow-Methods', 'POST, GET, OPTIONS, DELETE, PUT'
  res.json data, (result || 200)


exports.exec = (app, db, getUserFromDb, mods) ->

  def = (method, route, mid, callback) ->
    if !callback?
      callback = mid
      mid = []

    func = app[method]
    func.call app, route, mid, (req, res) ->
      try
        console.log(req.method, req.url)
        callback(req, res)
      catch ex
        exports.respond req, res, { err: 'Internal error: ' + ex.toString() }, 500


  responder = (req, res, fieldFilter) ->
    (err, data) ->
      if err
        if err.unauthorized
          res.header 'WWW-Authenticate', 'Basic realm="sally"'
          exports.respond req, res, { err: "unauthed" }, 401
        else
          exports.respond req, res, { err: err.toString() }, 400
      else
        outdata = JSON.parse(JSON.stringify(data))

        if !fieldFilter
          exports.respond req, res, outdata
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

          exports.respond req, res, outdata


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
          responder(req, res)({ unauthorized: true })
        else
          req.queryFilter = filter
          next()

    def 'get', "/#{modelName}", midFilter('read'), (req, res) ->
      db.list modelName, req.queryFilter, responder(req, res, mods[modelName].fieldFilter)

    def 'get', "/#{modelName}/:id", [validateId, midFilter('read')], (req, res) ->
      db.get modelName, req.params.id, req.queryFilter, responder(req, res, mods[modelName].fieldFilter)

    def 'del', "/#{modelName}/:id", [validateId, midFilter('write')], (req, res) ->
      db.del modelName, req.params.id, req.queryFilter, responder(req, res, mods[modelName].fieldFilter)

    def 'put', "/#{modelName}/:id", [validateId, midFilter('write')], (req, res) ->
      db.put modelName, req.params.id, req.body, req.queryFilter, responder(req, res, mods[modelName].fieldFilter)

    def 'get', "/meta/#{modelName}", (req, res) ->
      responder(req, res)(null, {
        owns: db.getOwnedModels(modelName).map((x) -> x.name)
        fields:db.getMetaFields(modelName)
      })

    if owners.length == 0
      def 'post', "/#{modelName}", [midFilter('create')], (req, res) ->
        db.post modelName, req.body, responder(req, res, mods[modelName].fieldFilter)

    owners.forEach (owner) ->
      def 'get', "/#{owner.plur}/:id/#{modelName}", [validateId, midFilter('read')], (req, res) ->
        db.listSub modelName, owner.sing, req.params.id, req.queryFilter, responder(req, res, mods[modelName].fieldFilter)

      def 'post', "/#{owner.plur}/:id/#{modelName}", [validateId, midFilter('create')], (req, res) ->
        db.postSub modelName, req.body, owner.sing, req.params.id, responder(req, res, mods[modelName].fieldFilter)

    manyToMany.forEach (many) ->
      def 'post', "/#{modelName}/:id/#{many.name}/:other", (req, res) ->
        db.postMany modelName, req.params.id, many.name, many.ref, req.params.other, responder(req, res)

      def 'post', "/#{many.name}/:other/#{modelName}/:id", (req, res) ->
        db.postMany modelName, req.params.id, many.name, many.ref, req.params.other, responder(req, res)

      def 'get', "/#{modelName}/:id/#{many.name}", (req, res) ->
        db.getMany modelName, req.params.id, many.name, responder(req, res)

      def 'get', "/#{many.name}/:id/#{modelName}", (req, res) ->
        db.getManyBackwards modelName, req.params.id, many.name, responder(req, res)

      def 'del', "/#{modelName}/:id/#{many.name}/:other", (req, res) ->
        db.get many.ref, req.params.other, (err, data) ->
          db.delMany modelName, req.params.id, many.name, many.ref, req.params.other, (innerErr) ->
            responder(req, res)(err || innerErr, data)

      def 'del', "/#{many.name}/:other/#{modelName}/:id", (req, res) ->
        db.get modelName, req.params.id, (err, data) ->
          db.delMany modelName, req.params.id, many.name, many.ref, req.params.other, (innerErr) ->
            responder(req, res)(err || innerErr, data)

  def 'get', '/', (req, res) ->
    exports.respond req, res,
      roots: db.getModels().filter((name) -> db.getOwners(name).length == 0)
      verbs: []

  def 'options', '*', (req, res) ->
    exports.respond(req, res, {}, 200)

  def 'all', '*', (req, res) ->
    exports.respond req, res, { err: 'No such resource' }, 400
