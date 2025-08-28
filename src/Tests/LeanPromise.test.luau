--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.LeanPromise)

local TestSuite = {}

-- Basic Settlement Tests

function TestSuite.TestBasicResolution()
    local didResolve = false
    local promise = Promise.new(function(resolve, reject)
        resolve("Success")
    end)

    promise:andThen(function(result)
        assert(result == "Success", "resolved with incorrect value")
        didResolve = true
        return nil
    end)

    task.wait(0.1) -- Allow time for async callbacks
    assert(didResolve, "Promise did not resolve")
end

function TestSuite.TestBasicRejection()
	local didReject = false
	local promise = Promise.new(function(resolve, reject)
		reject("Failure")
	end)

	promise:catch(function(reason)
		assert(reason == "Failure", "Rejected with incorrect reason")
		didReject = true
	end)

	task.wait(0.1)
	assert(didReject, "Promise did not reject")
end

function TestSuite.TestAsynchronousResolution()
	local didResolve = false
	local promise = Promise.new(function(resolve, reject)
		task.wait(0.2)
		resolve(true)
	end)

	promise:andThen(function(result)
		didResolve = true
        return nil
	end)

	-- Wait longer than the promise's internal delay
	task.wait(0.3)
	assert(didResolve, "Asynchronous promise did not resolve")
end

function TestSuite.TestExecutorErrorRejectsPromise()
	local didReject = false
	local promise = Promise.new(function(resolve, reject)
		error("Synchronous error inside executor")
	end)

	promise:catch(function(reason)
		didReject = true
	end)

	task.wait(0.1)
	assert(didReject, "Promise did not reject when executor errored")
end

-- Chaining Tests (andThen, catch, finally)

function TestSuite.TestAndThenChaining()
	local finalResult = 0
	Promise.resolve(10)
		:andThen(function(value)
			-- value should be 10
			return value + 5 -- should return 15
		end)
		:andThen(function(value)
			-- value should be 15
			finalResult = value * 2 -- should be 30
            return nil
		end)

	task.wait(0.1)
	assert(finalResult == 30, `Chaining result was incorrect. Expected 30, got {finalResult}`)
end

function TestSuite.TestCatchCanRecoverChain()
	local finalResult = ""
	Promise.reject("Initial Error")
		:catch(function(reason)
			-- Recover from the error by returning a new value
			return "Recovered Value"
		end)
		:andThen(function(value)
			-- This should now run with the recovered value
			finalResult = value
            return nil
		end)

	task.wait(0.1)
	assert(finalResult == "Recovered Value", "Chain did not recover after a .catch")
end

function TestSuite.TestFinallyRunsOnResolve()
	local didResolve = false
	local finallyRan = false
	Promise.resolve("Success")
		:andThen(function()
			didResolve = true
            return nil
		end)
		:finally(function()
			-- This should run after .andThen
			assert(didResolve, ".finally ran before .andThen")
			finallyRan = true
		end)

	task.wait(0.1)
	assert(finallyRan, ".finally did not run on a resolved promise")
end

function TestSuite.TestFinallyRunsOnReject()
	local didReject = false
	local finallyRan = false
	Promise.reject("Failure")
		:catch(function()
			didReject = true
		end)
		:finally(function()
			assert(didReject, ".finally ran before .catch")
			finallyRan = true
		end)

	task.wait(0.1)
	assert(finallyRan, ".finally did not run on a rejected promise")
end

function TestSuite.TestFinallyPassesThroughValue()
	local finalResult
	Promise.resolve(123)
		:finally(function()
			return "This value should be ignored"
		end)
		:andThen(function(value)
			finalResult = value
            return nil
		end)
		
	task.wait(0.1)
	assert(finalResult == 123, ".finally did not pass through the original resolved value")
end

-- Static Utility Tests (all, race)

function TestSuite.TestPromiseAllResolves()
	local promises = {
		Promise.new(function(r) task.wait(0.1); r("A") end),
		Promise.new(function(r) task.wait(0.2); r("B") end),
	}
	local didResolve = false

	Promise.all(promises):andThen(function(results)
		assert(results[1] == "A", "First result in .all is incorrect")
		assert(results[2] == "B", "Second result in .all is incorrect")
		didResolve = true
        return nil
	end)

	task.wait(0.3)
	assert(didResolve, "Promise.all did not resolve")
end

function TestSuite.TestPromiseAllRejects()
	local promises = {
		Promise.new(function(r) task.wait(0.2); r("A") end),
		Promise.new(function(_, r) task.wait(0.1); r("Early Failure") end),
	}
	local didReject = false

	Promise.all(promises):catch(function(reason: any?)
		assert(reason == "Early Failure", "Promise.all rejected with incorrect reason")
		didReject = true
	end)

	task.wait(0.3)
	assert(didReject, "Promise.all did not reject when one promise failed")
end

function TestSuite.TestPromiseRaceResolves()
	local promises = {
		Promise.new(function(r) task.wait(0.2); r("Slow") end),
		Promise.new(function(r) task.wait(0.1); r("Fast") end),
	}
	local didResolve = false

	Promise.race(promises):andThen(function(result)
		assert(result == "Fast", "Promise.race resolved with the wrong value")
		didResolve = true
        return nil
	end)

	task.wait(0.3)
	assert(didResolve, "Promise.race did not resolve")
end

function TestSuite.TestPromiseRaceRejects()
	local promises = {
		Promise.new(function(r) task.wait(0.2); r("Slow") end),
		Promise.new(function(_, r) task.wait(0.1); r("Fast Failure") end),
	}
	local didReject = false

	Promise.race(promises):catch(function(reason)
		assert(reason == "Fast Failure", "Promise.race rejected with the wrong reason")
		didReject = true
	end)

	task.wait(0.3)
	assert(didReject, "Promise.race did not reject")
end

return TestSuite
