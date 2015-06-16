(function() {
  var LockManager, Settings, rclient, redis;

  Settings = require("settings-sharelatex");

  redis = require("redis-sharelatex");

  rclient = redis.createClient(Settings.redis.web);

  module.exports = LockManager = {
    LOCK_TEST_INTERVAL: 50,
    MAX_LOCK_WAIT_TIME: 10000,
    LOCK_TTL: 10,
    tryLock: function(key, callback) {
      if (callback == null) {
        callback = function(err, gotLock) {};
      }
      return rclient.set(key, "locked", "EX", this.LOCK_TTL, "NX", function(err, gotLock) {
        if (err != null) {
          return callback(err);
        }
        if (gotLock === "OK") {
          return callback(err, true);
        } else {
          return callback(err, false);
        }
      });
    },
    getLock: function(key, callback) {
      var attempt, startTime;
      if (callback == null) {
        callback = function(error) {};
      }
      startTime = Date.now();
      return (attempt = function() {
        if (Date.now() - startTime > LockManager.MAX_LOCK_WAIT_TIME) {
          return callback(new Error("Timeout"));
        }
        return LockManager.tryLock(key, function(error, gotLock) {
          if (error != null) {
            return callback(error);
          }
          if (gotLock) {
            return callback(null);
          } else {
            return setTimeout(attempt, LockManager.LOCK_TEST_INTERVAL);
          }
        });
      })();
    },
    checkLock: function(key, callback) {
      if (callback == null) {
        callback = function(err, isFree) {};
      }
      return rclient.exists(key, function(err, exists) {
        if (err != null) {
          return callback(err);
        }
        exists = parseInt(exists);
        if (exists === 1) {
          return callback(err, false);
        } else {
          return callback(err, true);
        }
      });
    },
    releaseLock: function(key, callback) {
      return rclient.del(key, callback);
    },
    runWithLock: function(key, runner, callback) {
      if (runner == null) {
        runner = (function(releaseLock) {
          if (releaseLock == null) {
            releaseLock = function(error) {};
          }
        });
      }
      if (callback == null) {
        callback = (function(error) {});
      }
      return LockManager.getLock(key, function(error) {
        if (error != null) {
          return callback(error);
        }
        return runner(function(error1) {
          return LockManager.releaseLock(key, function(error2) {
            error = error1 || error2;
            if (error != null) {
              return callback(error);
            }
            return callback();
          });
        });
      });
    }
  };

}).call(this);
