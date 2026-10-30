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
	Defines a rich error object for handling Promise rejections.
]]

export type ErrorKind =
	"ExecutionError"
	| "AlreadyCancelled"
	| "NotResolvedInTime"
	| "TimedOut"
	| "Cancelled"
	| "ConnectivityError"
	| "DataStoreError"
	| "SessionConflict"
	| string

export type PromiseErrorOptions = {
	error: any,
	trace: string?,
	context: string?,
	kind: ErrorKind,
}

local ErrorKindEnum = {
	ExecutionError = "ExecutionError" :: "ExecutionError",
	AlreadyCancelled = "AlreadyCancelled" :: "AlreadyCancelled",
	NotResolvedInTime = "NotResolvedInTime" :: "NotResolvedInTime",
	TimedOut = "TimedOut" :: "TimedOut",
	Cancelled = "Cancelled" :: "Cancelled",
	ConnectivityError = "ConnectivityError" :: "ConnectivityError",
	DataStoreError = "DataStoreError" :: "DataStoreError",
	SessionConflict = "SessionConflict" :: "SessionConflict",
}
table.freeze(ErrorKindEnum)

local PromiseError = {}
PromiseError.__index = PromiseError

type PromiseErrorData = {
	error: string,
	trace: string?,
	context: string?,
	kind: ErrorKind,
	parent: PromiseError?,
	createdTick: number,
}

export type PromiseError = setmetatable<PromiseErrorData, typeof(PromiseError)>

function PromiseError.new(options: PromiseErrorOptions, parent: PromiseError?): PromiseError
	local self = setmetatable({}, PromiseError) :: PromiseError
	self.error = if options.error ~= nil then tostring(options.error) else "[This error has no error text.]"
	self.trace = options.trace
	self.context = options.context
	self.kind = options.kind
	self.parent = parent
	self.createdTick = os.clock()

	return self
end

function PromiseError.is(value: any): boolean
	return typeof(value) == "table" and getmetatable(value) == PromiseError
end

function PromiseError.isKind(value: any, kind: ErrorKind): boolean
	return PromiseError.is(value) and (value :: PromiseError).kind == kind
end

function PromiseError.extend(self: PromiseError, options: { kind: ErrorKind? }?): PromiseError
	const resolvedKind = if options and options.kind then options.kind else self.kind
	return PromiseError.new({
		error = self.error,
		trace = self.trace,
		context = self.context,
		kind = resolvedKind,
	}, self)
end

function PromiseError.getErrorChain(self: PromiseError): { PromiseError }
	local errorChain: { PromiseError } = { self }
	local current: PromiseError = self
	while current.parent do
		table.insert(errorChain, current.parent)
		current = current.parent
	end

	return errorChain
end

function PromiseError.__tostring(self: PromiseError): string
	local errorStrings = { `--- Promise Error ({self.kind}) ---` }
	for _, err in PromiseError.getErrorChain(self) do
		local parts: { string } = {}
		if err.trace then
			table.insert(parts, err.trace)
		else
			table.insert(parts, err.error)
		end
		if err.context then
			table.insert(parts, err.context)
		end
		table.insert(errorStrings, table.concat(parts, "\n"))
	end

	return table.concat(errorStrings, "\n\n")
end

return table.freeze({
	Kind = ErrorKindEnum,
	new = PromiseError.new,
	is = PromiseError.is,
	isKind = PromiseError.isKind,
})
