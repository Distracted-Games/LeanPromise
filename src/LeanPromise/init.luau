--!strict
--[[
	Copyright (c) 2019 Eryn L. K.
	https://github.com/evaera/roblox-lua-promise

	This library is a derivative work of the original Promise.lua library by evaera,
	licensed under the MIT License.

	---

	Copyright (c) 2026 Distracted Games

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.
]]

--[[
	A modern, robust, and strictly-typed Promise implementation for Luau.
	Designed to handle asynchronous operations like DataStore calls or asset loading
	in a clean, non-blocking, and readable way.

	LeanPromise is a refactored derivative of the Promise.lua library by evaera,
	architected to align with modern Luau idioms and a strict, type-safe workflow.
]]

const PromiseError = require("@self/PromiseError")

type PromiseError = PromiseError.PromiseError

export type StatusType = "Started" | "Resolved" | "Rejected" | "Cancelled"

const Status = {
	Started = "Started" :: "Started",
	Resolved = "Resolved" :: "Resolved",
	Rejected = "Rejected" :: "Rejected",
	Cancelled = "Cancelled" :: "Cancelled",
}
table.freeze(Status)

--[[
	Creates an xpcall error handler that wraps raw errors in a rich PromiseError.
]]
local function makeErrorHandler(traceback: string): (err: any) -> PromiseError
	return function(err: any): PromiseError
		if PromiseError.is(err) then
			return err
		end
		return PromiseError.new({
			error = err,
			kind = PromiseError.Kind.ExecutionError,
			trace = debug.traceback(tostring(err), 2),
			context = `Promise created at:\n{traceback}`,
		})
	end
end

--[[
	Safely invokes a callback with xpcall and captures its return values or PromiseError.
]]
local function runExecutor(traceback: string, callback: (...any) -> ...any, ...: any): (boolean, ...any)
	return xpcall(callback, makeErrorHandler(traceback), ...)
end

local Promise = {}
Promise.__index = Promise

type PromiseData<T> = {
	_status: StatusType,
	_values: { any }?,
	_valuesLength: number,
	_unhandledRejection: boolean,
	_parent: any,
	_reason: any,
	_consumers: { [any]: boolean },
	_fulfilledCallbacks: { (T) -> () },
	_rejectedCallbacks: { (any) -> () },
	_cancellationHook: (() -> ())?,
}

export type Promise<T = any> = setmetatable<PromiseData<T>, typeof(Promise)>

function Promise.is(value: any): boolean
	return typeof(value) == "table" and getmetatable(value) == Promise
end

function Promise.new<T>(executor: (
	resolve: (...any) -> (),
	reject: (any) -> (),
	onCancel: (cancellationHook: (() -> ())?) -> boolean
) -> ()): Promise<T>
	const traceback = debug.traceback(nil, 2)

	local self = setmetatable({}, Promise) :: Promise<T>
	self._status = Status.Started
	self._values = nil
	self._valuesLength = -1
	self._unhandledRejection = false
	self._reason = nil
	self._fulfilledCallbacks = {}
	self._rejectedCallbacks = {}
	self._cancellationHook = nil
	self._parent = nil
	self._consumers = {}

	local function resolve(...: any)
		if self._status ~= Status.Started then
			return
		end

		const valueCount = select("#", ...)
		self._status = Status.Resolved
		self._values = { ... }
		self._valuesLength = valueCount
		self._cancellationHook = nil

		const callbacks = table.clone(self._fulfilledCallbacks)
		table.clear(self._fulfilledCallbacks)
		table.clear(self._rejectedCallbacks)
		table.clear(self._consumers)

		for _, callback in callbacks do
			task.spawn(callback, ...)
		end
	end

	local function reject(reason: any)
		if self._status ~= Status.Started then
			return
		end

		self._status = Status.Rejected
		self._reason = reason
		self._unhandledRejection = true
		self._cancellationHook = nil

		const callbacks = table.clone(self._rejectedCallbacks)
		table.clear(self._fulfilledCallbacks)
		table.clear(self._rejectedCallbacks)
		table.clear(self._consumers)

		for _, callback in callbacks do
			task.spawn(callback, reason)
		end
	end

	local function onCancel(cancellationHook: (() -> ())?): boolean
		if cancellationHook then
			if self._status == Status.Cancelled then
				task.spawn(cancellationHook)
			else
				self._cancellationHook = cancellationHook
			end
		end

		return self._status == Status.Cancelled
	end

	task.spawn(function()
		const success, result = runExecutor(traceback, executor, resolve, reject, onCancel)
		if not success then
			reject(result)
		end
	end)

	return self
end

--[[
	Safely executes a chained handler and forwards its settlement to the next Promise.
]]
local function createChainedCallback(
	traceback: string,
	handler: (...any) -> ...any,
	resolve: (...any) -> (),
	reject: (any) -> (),
	cancelNext: () -> ()
): (...any) -> ()
	return function(...: any)
		const success, result = runExecutor(traceback, handler, ...)
		if not success then
			reject(result)
			return
		end

		if Promise.is(result) then
			const chainedPromise = result :: Promise<any>
			if chainedPromise._status == Status.Cancelled then
				cancelNext()
				return
			end
			chainedPromise:andThen(resolve, reject)
		else
			resolve(result)
		end
	end
end

function Promise.getStatus<T>(self: Promise<T>): StatusType
	return self._status
end

function Promise.andThen<T>(self: Promise<T>, onFulfilled: ((T) -> ...any)?, onRejected: ((any) -> ...any)?): Promise<any>
	if self._status == Status.Cancelled then
		local cancelledPromise = Promise.new(function() end)
		cancelledPromise:cancel()
		return cancelledPromise
	end

	if onRejected then
		self._unhandledRejection = false
	end

	const traceback = debug.traceback(nil, 2)
	local nextPromise: Promise<any>

	nextPromise = Promise.new(function(resolve, reject)
		const cancelNext = function()
			if nextPromise then
				nextPromise:cancel()
			end
		end

		const successCallback = if onFulfilled
			then createChainedCallback(traceback, onFulfilled :: any, resolve, reject, cancelNext)
			else resolve

		const failureCallback = if onRejected
			then createChainedCallback(traceback, onRejected, resolve, reject, cancelNext)
			else reject

		if self._status == Status.Started then
			table.insert(self._fulfilledCallbacks, successCallback)
			table.insert(self._rejectedCallbacks, failureCallback)
		elseif self._status == Status.Resolved then
			const values = self._values or {}
			task.spawn(successCallback, table.unpack(values, 1, self._valuesLength))
		elseif self._status == Status.Rejected then
			task.spawn(failureCallback, self._reason)
		end
	end)

	if self._status == Status.Started and nextPromise._status == Status.Started then
		nextPromise._parent = self
		self._consumers[nextPromise] = true
	end

	return nextPromise
end

function Promise.cancel<T>(self: Promise<T>)
	if self._status ~= Status.Started then
		return
	end

	self._status = Status.Cancelled

	if self._cancellationHook then
		const hook = self._cancellationHook
		self._cancellationHook = nil
		task.spawn(hook)
	end

	const parent = self._parent
	if parent then
		parent._consumers[self] = nil
		self._parent = nil
		if next(parent._consumers) == nil then
			parent:cancel()
		end
	end

	local consumersToCancel: { Promise<any> } = {}
	for consumer in self._consumers do
		table.insert(consumersToCancel, consumer)
	end
	table.clear(self._consumers)

	for _, consumer in consumersToCancel do
		consumer._parent = nil
		consumer:cancel()
	end

	table.clear(self._fulfilledCallbacks)
	table.clear(self._rejectedCallbacks)
end

function Promise.catch<T>(self: Promise<T>, onRejected: (any) -> ...any): Promise<any>
	return self:andThen(nil, onRejected)
end

function Promise.finally<T>(self: Promise<T>, onFinally: (() -> ...any)?): Promise<T>
	if not onFinally then
		return self
	end

	self._unhandledRejection = false
	const traceback = debug.traceback(nil, 2)

	if self._status == Status.Cancelled then
		task.spawn(runExecutor, traceback, onFinally)
		local cancelledPromise = Promise.new(function() end) :: Promise<T>
		cancelledPromise:cancel()
		return cancelledPromise
	end

	local finallyPromise: Promise<T>
	finallyPromise = Promise.new(function(resolve, reject, onCancel)
		onCancel(function()
			task.spawn(runExecutor, traceback, onFinally)
		end)

		local function finallyCallback()
			const success, result = runExecutor(traceback, onFinally)
			if not success then
				reject(result)
				return
			end

			local function passThroughOriginalOutcome()
				if self._status == Status.Resolved then
					const values = self._values or {}
					resolve(table.unpack(values, 1, self._valuesLength))
				elseif self._status == Status.Rejected then
					reject(self._reason)
				end
			end

			if Promise.is(result) then
				const returnedPromise = result :: Promise<any>
				if returnedPromise._status == Status.Cancelled then
					if finallyPromise then
						finallyPromise:cancel()
					end
					return
				end
				returnedPromise:andThen(passThroughOriginalOutcome, reject)
			else
				passThroughOriginalOutcome()
			end
		end

		if self._status == Status.Started then
			table.insert(self._fulfilledCallbacks, finallyCallback :: any)
			table.insert(self._rejectedCallbacks, finallyCallback :: any)
		else
			task.spawn(finallyCallback)
		end
	end) :: Promise<T>

	if self._status == Status.Started and finallyPromise._status == Status.Started then
		finallyPromise._parent = self
		self._consumers[finallyPromise] = true
	end

	return finallyPromise
end

function Promise.resolve<T>(value: T): Promise<T>
	return Promise.new(function(resolve)
		resolve(value)
	end)
end

function Promise.reject(reason: any): Promise<any>
	return Promise.new(function(_, reject)
		reject(reason)
	end)
end

--[[
	Accepts an array of Promises and returns a new Promise that:
	- Resolves with an array of all resolved values once every input Promise resolves.
	- Rejects immediately if any input Promise rejects.
]]
function Promise.all<T>(promises: { Promise<T> }): Promise<{ T }>
	const traceback = debug.traceback(nil, 2)

	if typeof(promises) ~= "table" then
		error(`Promise.all expects a table of promises, got: {typeof(promises)}`, 2)
	end

	if #promises == 0 then
		return Promise.resolve({} :: { T })
	end

	return Promise.new(function(resolve, reject, onCancel)
		local resolvedValues: { T } = {}
		local promisesRemaining = #promises
		local isSettled = false

		onCancel(function()
			for _, promise in promises do
				if Promise.is(promise) then
					promise:cancel()
				end
			end
		end)

		for index, promise in promises do
			if not Promise.is(promise) then
				isSettled = true
				reject(PromiseError.new({
					error = `Value at index {index} is not a Promise.`,
					kind = PromiseError.Kind.ExecutionError,
					trace = traceback,
				}))
				return
			end

			local function onFulfilled(value: T)
				if isSettled then
					return
				end
				resolvedValues[index] = value
				promisesRemaining -= 1

				if promisesRemaining <= 0 then
					isSettled = true
					resolve(resolvedValues)
				end
			end

			local function onRejected(err: any)
				if isSettled then
					return
				end
				isSettled = true
				reject(err)
			end

			promise:andThen(onFulfilled, onRejected)
		end
	end) :: Promise<{ T }>
end

--[[
	Accepts an array of Promises and returns a new Promise that settles as soon as
	the first input Promise resolves or rejects.
]]
function Promise.race<T>(promises: { Promise<T> }): Promise<T>
	const traceback = debug.traceback(nil, 2)

	if typeof(promises) ~= "table" then
		error(`Promise.race expects a table of promises, got: {typeof(promises)}`, 2)
	end

	return Promise.new(function(resolve, reject, onCancel)
		local isSettled = false

		onCancel(function()
			for _, promise in promises do
				if Promise.is(promise) then
					promise:cancel()
				end
			end
		end)

		for index, promise in promises do
			if not Promise.is(promise) then
				isSettled = true
				reject(PromiseError.new({
					error = `Value at index {index} is not a Promise.`,
					kind = PromiseError.Kind.ExecutionError,
					trace = traceback,
				}))
				return
			end

			local function onFulfilled(value: T)
				if not isSettled then
					isSettled = true
					resolve(value)
				end
			end

			local function onRejected(err: any)
				if not isSettled then
					isSettled = true
					reject(err)
				end
			end

			promise:andThen(onFulfilled, onRejected)
		end
	end) :: Promise<T>
end

return table.freeze({
	Status = Status,
	Error = PromiseError,
	is = Promise.is,
	new = Promise.new,
	all = Promise.all,
	race = Promise.race,
	resolve = Promise.resolve,
	reject = Promise.reject,
})
