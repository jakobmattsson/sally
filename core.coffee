_ = require 'underscore'
mongoose = require 'mongoose'
mongojs = require 'mongojs'
express = require 'express'
ObjectId = mongoose.Schema.ObjectId

app = express.createServer()
app.use express.bodyParser()



db = require('./db')

exports.defModel = db.defModel
exports.ObjectId = db.ObjectId

exports.exec = () ->
  db.exec()

  def = (method, route, mid, callback) ->
    if !callback?
      callback = mid
      mid = []

    # console.log method, route
    app[method](route, mid, callback)

  responder = (res) ->
    (err, data) ->
      if err
        res.json { err: err.toString() }, 400
      else
        res.json(massageResult(JSON.parse(JSON.stringify(data))))

  validateId = (req, res, next) ->
    try
      mongoose.mongo.ObjectID(req.params.id)
    catch ex
      res.json { err: 'No such id' }, 400 # duplication. can this be extracted out?
      return
    next()

  massageOne = (x) ->
    x.id = x._id
    delete x._id
    x

  massageResult = (r2) -> if Array.isArray r2 then r2.map massageOne else massageOne r2


  Object.keys(db.models).forEach (modelName) ->

    outers = db.getOwners(modelName)
    manyToMany = db.getManyToMany(modelName)

    def 'get', "/#{modelName}", (req, res) ->
      db.list modelName, responder(res)

    def 'get', "/#{modelName}/:id", validateId, (req, res) ->
      db.get modelName, req.params.id, responder(res)

    def 'del', "/#{modelName}/:id", validateId, (req, res) ->
      db.del modelName, req.params.id, responder(res)

    def 'put', "/#{modelName}/:id", validateId, (req, res) ->
      db.put modelName, req.params.id, req.body, responder(res)

    if outers.length == 0
      def 'post', "/#{modelName}", (req, res) ->
        db.post modelName, req.body, responder(res)

    outers.forEach (outer) ->
      def 'get', "/#{outer.plur}/:id/#{modelName}", validateId, (req, res) ->
        db.listSub modelName, outer.sing, req.params.id, responder(res)

      def 'post', "/#{outer.plur}/:id/#{modelName}", validateId, (req, res) ->
        db.postSub modelName, req.body, outer.sing, req.params.id, responder(res)

    manyToMany.forEach (many) ->
      def 'post', "/#{modelName}/:id/#{many.name}/:other", (req, res) ->
        db.postMany modelName, req.params.id, many.name, many.ref, req.params.other, responder(res)

      def 'post', "/#{many.name}/:other/#{modelName}/:id", (req, res) ->
        db.postMany modelName, req.params.id, many.name, many.ref, req.params.other, responder(res)

      def 'get', "/#{modelName}/:id/#{many.name}", (req, res) ->
        db.getMany modelName, req.params.id, many.name, responder(res)

      def 'get', "/#{many.name}/:id/#{modelName}", (req, res) ->
        db.getManyBackwards modelName, req.params.id, many.name, responder(res)

      def 'del', "/#{modelName}/:id/#{many.name}/:other", (req, res) ->
        db.get many.ref, req.params.other, (err, data) ->
          db.delMany modelName, req.params.id, many.name, many.ref, req.params.other, (innerErr) ->
            responder(res)(err || innerErr, data)

      def 'del', "/#{many.name}/:other/#{modelName}/:id", (req, res) ->
        db.get modelName, req.params.id, (err, data) ->
          db.delMany modelName, req.params.id, many.name, many.ref, req.params.other, (innerErr) ->
            responder(res)(err || innerErr, data)

  app.get '/', (req, res) ->
    res.json
      roots: ['companies'] # generera istället
      verbs: []

  app.all '*', (req, res) ->
    res.json { err: 'No such resource' }, 400

  app.listen 3000
