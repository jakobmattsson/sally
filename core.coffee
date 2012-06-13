_ = require 'underscore'
express = require 'express'

app = express.createServer()
app.use express.bodyParser()

exports.exec = (db) ->

  def = (method, route, mid, callback) ->
    if !callback?
      callback = mid
      mid = []

    # console.log method, route
    app[method](route, mid, callback)

  respond = (req, res, data, result) ->
    res.header 'Access-Control-Allow-Origin', req.headers.origin
    res.header 'Access-Control-Allow-Credentials', 'true'
    res.header 'Access-Control-Allow-Headers', 'Authorization'
    res.header 'Access-Control-Allow-Methods', 'POST, GET, OPTIONS, DELETE, PUT'
    res.json data, (result || 200)

  responder = (req, res) ->
    (err, data) ->
      if err
        if err.unauthorized
          res.header 'WWW-Authenticate', 'Basic realm="sally"'
          respond req, res, { err: "unauthed" }, 401
        else
          respond req, res, { err: err.toString() }, 400
      else
        respond req, res, massageResult(JSON.parse(JSON.stringify(data)))

  validateId = (req, res, next) ->
    if db.isValidId(req.params.id)
      next()
    else
      respond req, res, { err: 'No such id' }, 400 # duplication. can this be extracted out?

  massageOne = (x) ->
    x.id = x._id
    delete x._id
    x

  massageResult = (r2) -> if Array.isArray r2 then r2.map massageOne else massageOne r2

  db.getModels().forEach (modelName) ->

    owners = db.getOwners(modelName)
    manyToMany = db.getManyToMany(modelName)

    def 'get', "/#{modelName}", (req, res) ->
      db.getFilter req, modelName, (err, filter) ->
        if !filter?
          responder(req, res)({ unauthorized: true })
        else
          db.list modelName, filter, responder(req, res)

    def 'get', "/#{modelName}/:id", validateId, (req, res) ->
      db.get modelName, req.params.id, responder(req, res)

    def 'del', "/#{modelName}/:id", validateId, (req, res) ->
      db.del modelName, req.params.id, responder(req, res)

    def 'put', "/#{modelName}/:id", validateId, (req, res) ->
      db.put modelName, req.params.id, req.body, responder(req, res)

    def 'get', "/meta/#{modelName}", (req, res) ->
      responder(req, res)(null, {
        owns: db.getOwnedModels(modelName).map((x) -> x.name)
        fields:db.getMetaFields(modelName)
      })

    if owners.length == 0
      def 'post', "/#{modelName}", (req, res) ->
        db.post modelName, req.body, responder(req, res)

    owners.forEach (owner) ->
      def 'get', "/#{owner.plur}/:id/#{modelName}", validateId, (req, res) ->
        db.listSub modelName, owner.sing, req.params.id, responder(req, res)

      def 'post', "/#{owner.plur}/:id/#{modelName}", validateId, (req, res) ->
        db.postSub modelName, req.body, owner.sing, req.params.id, responder(req, res)

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

  app.get '/', (req, res) ->
    respond req, res,
      roots: db.getModels().filter((name) -> db.getOwners(name).length == 0)
      verbs: []

  app.options '*', (req, res) ->
    respond(req, res, {}, 200)

  app.all '*', (req, res) ->
    respond req, res, { err: 'No such resource' }, 400

  app.listen 3000