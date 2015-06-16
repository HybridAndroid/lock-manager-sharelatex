sinon = require('sinon')
chai = require('chai')
should = chai.should()
expect = chai.expect
modulePath = "../../../app/js/LockManager.js"
SandboxedModule = require('sandboxed-module')

describe "LockManager", ->
	beforeEach ->
		@Settings = 		
			redis:
				web:{}
		@rclient = {}
		@createClientStub = sinon.stub().returns(@rclient)
		@LockManager = SandboxedModule.require modulePath, requires:
			"redis-sharelatex":
				createClient: @createClientStub
			"settings-sharelatex": @Settings
		@key = "lock-key"
		@callback = sinon.stub()

	describe "setup", ->
		it "should pass the redis connection string to redis", (done)->
			connectionString = "redis-hello@world"
			@LockManager = @LockManager(connectionString)
			@createClientStub.calledWith(connectionString).should.equal true
			done()



	describe "checkLock", ->
		describe "when the lock is taken", ->
			beforeEach ->
				@LockManager = @LockManager()
				@rclient.exists = sinon.stub().callsArgWith(1, null, "1")
				@LockManager.checkLock @key, @callback

			it "should check the lock in redis", ->
				@rclient.exists
					.calledWith(@key)
					.should.equal true

			it "should return the callback with false", ->
				@callback.calledWith(null, false).should.equal true

		describe "when the lock is free", ->
			beforeEach ->
				@LockManager = @LockManager()		
				@rclient.exists = sinon.stub().callsArgWith(1, null, "0")
				@LockManager.checkLock @key, @callback

			it "should return the callback with true", ->
				@callback.calledWith(null, true).should.equal true

	describe "forceTakeLock", ->
		describe "when the lock is taken", ->
			beforeEach ->
				@LockManager = @LockManager()
				@rclient.set = sinon.stub().callsArgWith(4, null, null)
				@LockManager.forceTakeLock @key, @callback

			it "should set the lock in redis", ->
				@rclient.set
					.calledWith(@key, "locked", "EX", @LockManager.LOCK_TTL)
					.should.equal true

			it "should call the callback", ->
				@callback.called.should.equal true


	describe "tryLock", ->
		describe "when the lock is taken", ->
			beforeEach ->
				@LockManager = @LockManager()
				@rclient.set = sinon.stub().callsArgWith(5, null, null)
				@LockManager.tryLock @key, @callback

			it "should set the lock in redis", ->
				@rclient.set
					.calledWith(@key, "locked", "EX", @LockManager.LOCK_TTL, "NX")
					.should.equal true

			it "should return the callback with false", ->
				@callback.calledWith(null, false).should.equal true

		describe "when the lock is free", ->
			beforeEach ->
				@LockManager = @LockManager()
				@rclient.set = sinon.stub().callsArgWith(5, null, "OK")
				@LockManager.tryLock @key, @callback

			it "should return the callback with true", ->
				@callback.calledWith(null, true).should.equal true

	describe "deleteLock", ->
		beforeEach -> 
			beforeEach ->
				@LockManager = @LockManager()
				@rclient.del = sinon.stub().callsArg(1)
				@LockManager.deleteLock @key, @callback

			it "should delete the lock in redis", ->
				@rclient.del
					.calledWith(key)
					.should.equal true

			it "should call the callback", ->
				@callback.called.should.equal true

	describe "getLock", ->
		describe "when the lock is not taken", ->
			beforeEach (done) ->
				@LockManager = @LockManager()
				@LockManager.tryLock = sinon.stub().callsArgWith(1, null, true)
				@LockManager.getLock @key, (args...) =>
					@callback(args...)
					done()

			it "should try to get the lock", ->
				@LockManager.tryLock
					.calledWith(@key)
					.should.equal true

			it "should only need to try once", ->
				@LockManager.tryLock.callCount.should.equal 1

			it "should return the callback", ->
				@callback.calledWith(null).should.equal true

		describe "when the lock is initially set", ->
			beforeEach (done) ->
				@LockManager = @LockManager()
				startTime = Date.now()
				@LockManager.LOCK_TEST_INTERVAL = 5
				@LockManager.tryLock = (doc_id, callback = (error, isFree) ->) ->
					if Date.now() - startTime < 20
						callback null, false
					else
						callback null, true
				sinon.spy @LockManager, "tryLock"

				@LockManager.getLock @key, (args...) =>
					@callback(args...)
					done()

			it "should call tryLock multiple times until free", ->
				(@LockManager.tryLock.callCount > 1).should.equal true

			it "should return the callback", ->
				@callback.calledWith(null).should.equal true

		describe "when the lock times out", ->
			beforeEach (done) ->
				@LockManager = @LockManager()
				time = Date.now()
				@LockManager.MAX_LOCK_WAIT_TIME = 5
				@LockManager.tryLock = sinon.stub().callsArgWith(1, null, false)
				@LockManager.getLock @key, (args...) =>
					@callback(args...)
					done()

			it "should return the callback with an error", ->
				@callback.calledWith(new Error("timeout")).should.equal true

	describe "runWithLock", ->
		describe "with successful run", ->
			beforeEach ->
				@LockManager = @LockManager()
				@runner = (releaseLock = (error) ->) ->
					releaseLock()
				sinon.spy @, "runner"
				@LockManager.getLock = sinon.stub().callsArg(1)
				@LockManager.releaseLock = sinon.stub().callsArg(1)
				@LockManager.runWithLock @key, @runner, @callback

			it "should get the lock", ->
				@LockManager.getLock
					.calledWith(@key)
					.should.equal true

			it "should run the passed function", ->
				@runner.called.should.equal true

			it "should release the lock", ->
				@LockManager.releaseLock
					.calledWith(@key)
					.should.equal true

			it "should call the callback", ->
				@callback.called.should.equal true

		describe "when the runner function returns an error", ->
			beforeEach ->
				@LockManager = @LockManager()
				@error = new Error("oops")
				@runner = (releaseLock = (error) ->) =>
					releaseLock(@error)
				sinon.spy @, "runner"
				@LockManager.getLock = sinon.stub().callsArg(1)
				@LockManager.releaseLock = sinon.stub().callsArg(1)
				@LockManager.runWithLock @key, @runner, @callback

			it "should release the lock", ->
				@LockManager.releaseLock
					.calledWith(@key)
					.should.equal true

			it "should call the callback with the error", ->
				@callback.calledWith(@error).should.equal true
