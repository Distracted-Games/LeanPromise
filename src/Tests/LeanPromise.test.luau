--!strict
const Promise = require("../LeanPromise")
const PromiseError = require("../LeanPromise/PromiseError")

local TestSuite = {}

--------------------------------------------------------------------------------
-- Basic Settlement & Error Handling Tests
--------------------------------------------------------------------------------

function TestSuite.TestBasicResolution()
	local didResolve = false
	const promise = Promise.new(function(resolve)
		resolve("Success")
	end)

	promise:andThen(function(result)
		assert(result == "Success", "Resolved with incorrect value")
		didResolve = true
	end)

	task.wait(0.05)
	assert(didResolve, "Promise did not resolve")
end

function TestSuite.TestBasicRejection()
	local didReject = false
	const promise = Promise.new(function(_, reject)
		reject("Failure")
	end)

	promise:catch(function(reason)
		assert(reason == "Failure", "Rejected with incorrect reason")
		didReject = true
	end)

	task.wait(0.05)
	assert(didReject, "Promise did not reject")
end

function TestSuite.TestAsynchronousResolution()
	local didResolve = false
	const promise = Promise.new(function(resolve)
		task.wait(0.05)
		resolve(true)
	end)

	promise:andThen(function(result)
		assert(result == true, "Expected true")
		didResolve = true
	end)

	task.wait(0.1)
	assert(didResolve, "Asynchronous promise did not resolve")
end

function TestSuite.TestExecutorErrorRejectsPromise()
	local caughtReason: any = nil
	const promise = Promise.new(function()
		error("Synchronous error inside executor")
	end)

	promise:catch(function(reason)
		caughtReason = reason
	end)

	task.wait(0.05)
	assert(caughtReason ~= nil, "Promise did not reject when executor errored")
	assert(PromiseError.isKind(caughtReason, PromiseError.Kind.ExecutionError), "Expected ExecutionError PromiseError")
end

function TestSuite.TestThrownTableErrorPreservesIdentity()
	const customErrorTable = { code = 5, detail = "CustomFailure" }
	local caughtFromExecutor: any = nil
	local caughtFromChain: any = nil

	Promise.new(function()
		error(customErrorTable)
	end):catch(function(reason)
		caughtFromExecutor = reason
	end)

	Promise.resolve(1)
		:andThen(function()
			error(customErrorTable)
		end)
		:catch(function(reason)
			caughtFromChain = reason
		end)

	task.wait(0.05)
	assert(caughtFromExecutor == customErrorTable, "Executor stringified thrown table instead of preserving identity")
	assert(caughtFromChain == customErrorTable, "Chained handler stringified thrown table instead of preserving")
end

--------------------------------------------------------------------------------
-- Chaining, Multi-Return, & Adoption Tests
--------------------------------------------------------------------------------

function TestSuite.TestAndThenChaining()
	local finalResult = 0
	Promise.resolve(10)
		:andThen(function(value)
			return value + 5
		end)
		:andThen(function(value)
			finalResult = value * 2
		end)

	task.wait(0.05)
	assert(finalResult == 30, `Chaining result was incorrect. Expected 30, got {finalResult}`)
end

function TestSuite.TestMultiValueAndVoidReturns()
	local argCount = -1
	local firstVal: any = nil
	local secondVal: any = "unset"
	local thirdVal: any = nil
	local voidArgCount = -1

	Promise.new(function(resolve)
		resolve("A", nil, "C")
	end)
		:andThen(function(...: any)
			return ...
		end)
		:andThen(function(...: any)
			argCount = select("#", ...)
			firstVal, secondVal, thirdVal = ...
		end)
		:andThen(function(...: any)
			voidArgCount = select("#", ...)
		end)

	task.wait(0.05)
	assert(argCount == 3, `Expected 3 unpacked values including nil hole, got {argCount}`)
	assert(firstVal == "A" and secondVal == nil and thirdVal == "C", "Multi-return values with nil hole corrupted")
	assert(voidArgCount == 0, `Void handler should resolve with 0 values, got {voidArgCount}`)
end

function TestSuite.TestPromiseAdoptionInResolve()
	const adoptedStatic = Promise.resolve(Promise.resolve(42))
	const unwrappedValue: any = adoptedStatic:await()
	assert(unwrappedValue == 42, `Promise.resolve(promise) failed to unwrap, got {tostring(unwrappedValue)}`)

	const adoptedDynamic = Promise.new(function(resolve)
		resolve(Promise.delay(0.02):andThen(function()
			return "AdoptedAsync"
		end))
	end)
	const dynamicVal: any = adoptedDynamic:await()
	assert(dynamicVal == "AdoptedAsync", "Dynamic resolve(promise) failed to adopt inner promise")

	-- Self-resolution guard:
	local selfPromise: Promise.Promise<any>
	local resolveSelf: (...any) -> ()
	selfPromise = Promise.new(function(resolve)
		resolveSelf = resolve
	end)
	resolveSelf(selfPromise)

	const okSelf, selfErr = pcall(function()
		return selfPromise:await()
	end)
	assert(not okSelf and PromiseError.isKind(selfErr, PromiseError.Kind.ExecutionError), "Self-resolve must reject")
end

function TestSuite.TestCatchCanRecoverChain()
	local finalResult = ""
	Promise.reject("Initial Error")
		:catch(function()
			return "Recovered Value"
		end)
		:andThen(function(value)
			finalResult = value
		end)

	task.wait(0.05)
	assert(finalResult == "Recovered Value", "Chain did not recover after a :catch()")
end

function TestSuite.TestFinallyRunsOnResolveAndAwaitsInnerPromise()
	local didResolve = false
	local observedStatus: Promise.StatusType? = nil
	local innerCompletedBeforeDownstream = false

	const finalValue = Promise.resolve(123)
		:andThen(function(val)
			didResolve = true
			return val
		end)
		:finally(function(status)
			assert(didResolve, ":finally() ran before :andThen()")
			observedStatus = status
			return Promise.delay(0.03):andThen(function()
				innerCompletedBeforeDownstream = true
				return "IgnoredValue"
			end)
		end)
		:await()

	assert(observedStatus == Promise.Status.Resolved, "Expected Resolved status in onFinally")
	assert(innerCompletedBeforeDownstream, ":finally() did not wait for returned inner promise")
	assert(finalValue == 123, ":finally() did not pass through original resolved value")
end

function TestSuite.TestFinallyPreservesRejectionAndStatus()
	local observedStatus: Promise.StatusType? = nil
	const chained = Promise.reject("Boom"):finally(function(status)
		observedStatus = status
	end)

	const ok, err = pcall(function()
		return chained:await()
	end)
	assert(observedStatus == Promise.Status.Rejected, "Expected Rejected status in onFinally")
	assert(not ok and err == "Boom", `:finally() did not preserve rejection 'Boom', got {tostring(err)}`)
end

--------------------------------------------------------------------------------
-- Cancellation Lifecycle & Claude Repro Regression Tests
--------------------------------------------------------------------------------

function TestSuite.TestRepro1CancelledAndThenSiblingDoesNotRun()
	local doomedHandlerRan = false
	local survivorValue: string? = nil

	const root = Promise.new(function(resolve)
		task.delay(0.05, resolve, "value")
	end)

	const doomed = root:andThen(function()
		doomedHandlerRan = true
	end)

	root:andThen(function(val)
		survivorValue = val
	end)

	doomed:cancel()
	task.wait(0.1)

	assert(not doomedHandlerRan, "Cancelled andThen handler must not run when parent settles for sibling")
	assert(survivorValue == "value", "Sibling consumer should still receive resolved value")
end

function TestSuite.TestRepro2FinallyRunsAtMostOnceOnCancel()
	-- Case A: Cancel finally while parent stays alive via another consumer
	local runsA = 0
	local observedStatusA: Promise.StatusType? = nil
	const parent = Promise.new(function(resolve)
		task.delay(0.05, resolve, "ok")
	end)
	parent:andThen(function() end)

	parent
		:finally(function(status)
			runsA += 1
			observedStatusA = status
		end)
		:cancel()

	task.wait(0.1)
	assert(runsA == 1, `Expected onFinally to run once on cancel, got {runsA}`)
	assert(observedStatusA == Promise.Status.Cancelled, "Expected Cancelled status when finally is cancelled")

	-- Case B: Cancel finally while a returned inner promise is still pending
	local runsB = 0
	local innerCancelFired = false
	const outerFinally = Promise.resolve("done"):finally(function()
		runsB += 1
		return Promise.new(function(_, _, onCancel)
			onCancel(function()
				innerCancelFired = true
			end)
		end)
	end)

	task.wait()
	outerFinally:cancel()
	task.wait(0.05)

	assert(runsB == 1, `Expected onFinally to run once when cancelled during inner promise, got {runsB}`)
	assert(innerCancelFired, "Cancelling finallyPromise should cancel pending inner promise")
end

function TestSuite.TestRepro3SettledParentReturningCancelledPromise()
	const dead = Promise.new(function() end)
	dead:cancel()

	const result = Promise.resolve(1):andThen(function()
		return dead
	end)

	task.wait()
	assert(
		result:getStatus() == Promise.Status.Cancelled,
		`Expected Cancelled status instead of hanging Started, got {result:getStatus()}`
	)
end

function TestSuite.TestRepro4CancellationPropagatesThroughReturnedPromise()
	-- Direction 1: Cancelling outer cancels inner pending promise
	local innerCancelled = false
	const outer = Promise.resolve(1):andThen(function()
		return Promise.new(function(_, _, onCancel)
			onCancel(function()
				innerCancelled = true
			end)
		end)
	end)

	task.wait()
	outer:cancel()
	task.wait()

	assert(innerCancelled, "Cancelling outer promise must cancel inner returned promise")
	assert(outer:getStatus() == Promise.Status.Cancelled, "Outer promise must be Cancelled")

	-- Direction 2: Cancelling inner directly cancels outer instead of hanging
	local innerRef: Promise.Promise<any>? = nil
	const outer2 = Promise.resolve(1):andThen(function()
		const p = Promise.new(function() end)
		innerRef = p
		return p
	end)

	task.wait()
	assert(innerRef ~= nil, "Inner promise was not created")
	innerRef:cancel()
	task.wait()

	assert(outer2:getStatus() == Promise.Status.Cancelled, "Cancelling inner promise must cancel outer consumer")
end

function TestSuite.TestCancelStopsExecutorThreadAndSettleClearsParent()
	local continuedAfterCancel = false
	const slow = Promise.new(function(resolve)
		task.wait(0.05)
		continuedAfterCancel = true
		resolve("done")
	end)

	task.wait(0.01)
	slow:cancel()
	task.wait(0.08)

	assert(not continuedAfterCancel, "Cancelling a promise should cancel its suspended executor thread")

	const root: Promise.Promise<number> = Promise.new(function(resolve)
		task.delay(0.02, resolve, 99)
	end)
	const child = root:andThen(function(v)
		return v + 1
	end)
	assert(child._parent == root, "Pending child should reference parent before settlement")
	assert(child:await() == 100, "Child resolved wrong value")
	assert(child._parent == nil, "Settled child must clear _parent for GC")
end

--------------------------------------------------------------------------------
-- Static Combinators (all, race), delay, await, & PromiseError Tests
--------------------------------------------------------------------------------

function TestSuite.TestPromiseAllResolvesAndValidates()
	const emptyResult = Promise.all({}):await()
	assert(#emptyResult == 0, "Promise.all({}) should resolve to an empty table")

	const okInvalid = pcall(function()
		return Promise.all({ Promise.resolve(1), "NotAPromise" :: any })
	end)
	assert(not okInvalid, "Promise.all should throw synchronously when given non-Promise elements")

	const results = Promise.all({
		Promise.delay(0.03):andThen(function()
			return "A"
		end),
		Promise.delay(0.01):andThen(function()
			return "B"
		end),
	}):await()

	assert(results[1] == "A" and results[2] == "B", "Promise.all did not preserve input order")
end

function TestSuite.TestPromiseAllRejectsAndRespectsSharedConsumers()
	local unsharedLoserCancelled = false
	local sharedSiblingCancelled = false
	local sharedSiblingResult: string? = nil

	const unsharedLoser = Promise.new(function(resolve, _, onCancel)
		onCancel(function()
			unsharedLoserCancelled = true
		end)
		task.delay(0.1, resolve, "Unshared")
	end)

	const sharedPromise = Promise.new(function(resolve, _, onCancel)
		onCancel(function()
			sharedSiblingCancelled = true
		end)
		task.delay(0.06, resolve, "SharedSuccess")
	end)
	sharedPromise:andThen(function(val)
		sharedSiblingResult = val
	end)

	const failing = Promise.new(function(_: (string) -> (), reject)
		task.delay(0.02, reject, "EarlyFailure")
	end)

	const ok, err: any = pcall(function()
		return Promise.all({ unsharedLoser, sharedPromise, failing }):await()
	end)

	assert(not ok and err == "EarlyFailure", `Expected EarlyFailure rejection, got {tostring(err)}`)
	task.wait(0.08)

	assert(unsharedLoserCancelled, "Promise.all rejection should cancel unshared pending promises")
	assert(not sharedSiblingCancelled, "Promise.all must NOT cancel input promises that have other consumers")
	assert(sharedSiblingResult == "SharedSuccess", "Shared input promise should still resolve for other consumer")
end

function TestSuite.TestPromiseRaceSettlesAndCancelsUnsharedLosers()
	local unsharedSlowCancelled = false
	local sharedSlowCancelled = false

	const unsharedSlow = Promise.new(function(resolve, _, onCancel)
		onCancel(function()
			unsharedSlowCancelled = true
		end)
		task.delay(0.1, resolve, "UnsharedSlow")
	end)

	const sharedSlow = Promise.new(function(resolve, _, onCancel)
		onCancel(function()
			sharedSlowCancelled = true
		end)
		task.delay(0.1, resolve, "SharedSlow")
	end)
	sharedSlow:andThen(function() end)

	const fastWinner = Promise.delay(0.02):andThen(function()
		return "Fast"
	end)

	const winner = Promise.race({ unsharedSlow, sharedSlow, fastWinner }):await()
	assert(winner == "Fast", `Expected Fast winner, got {tostring(winner)}`)
	task.wait()

	assert(unsharedSlowCancelled, "Promise.race should cancel unshared losing promises")
	assert(not sharedSlowCancelled, "Promise.race must NOT cancel shared losing promises")
end

function TestSuite.TestPromiseDelayAndAwaitSemantics()
	const elapsed = Promise.delay(0.03):await()
	assert(typeof(elapsed) == "number" and elapsed >= 0.02, `Unexpected delay elapsed: {tostring(elapsed)}`)

	-- Cancelled await throws AlreadyCancelled PromiseError:
	const toCancel = Promise.delay(0.5)
	task.delay(0.02, function()
		toCancel:cancel()
	end)

	const okCancel, cancelErr = pcall(function()
		return toCancel:await()
	end)
	assert(
		not okCancel and PromiseError.isKind(cancelErr, PromiseError.Kind.AlreadyCancelled),
		`Expected AlreadyCancelled PromiseError from cancelled await(), got {tostring(cancelErr)}`
	)

	-- Sibling consumer cancel does not kill a promise that is currently being awaited:
	const awaitedRoot = Promise.delay(0.04):andThen(function()
		return "Survived"
	end)
	const sibling = awaitedRoot:andThen(function() end)
	task.delay(0.01, function()
		sibling:cancel()
	end)
	assert(awaitedRoot:await() == "Survived", "Sibling cancellation killed an actively awaited promise")
end

function TestSuite.TestPromiseErrorExtendDoesNotDuplicateTrace()
	const baseErr = PromiseError.new({
		error = "Root failure",
		trace = "RootTraceLine1",
		context = "RootContextBlock",
		kind = PromiseError.Kind.ExecutionError,
	})

	const extended = baseErr:extend({
		context = "ChildExtraContext",
		kind = PromiseError.Kind.TimedOut,
	})

	assert(PromiseError.isKind(extended, PromiseError.Kind.TimedOut), "Extended kind did not update")
	const formatted = tostring(extended)
	const _, rootContextCount = string.gsub(formatted, "RootContextBlock", "")
	const _, childContextCount = string.gsub(formatted, "ChildExtraContext", "")
	assert(rootContextCount == 1, `Expected RootContextBlock once in tostring, appeared {rootContextCount} times`)
	assert(childContextCount == 1, `Expected ChildExtraContext once in tostring, appeared {childContextCount} times`)
end

return TestSuite
