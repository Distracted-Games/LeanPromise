# LeanPromise

A modern, robust, and strictly-typed Promise implementation for Luau. This library is a complete, feature-complete refactor of the popular `Promise.lua` library by evaera, architected to align with modern Luau idioms and a professional, type-safe workflow.

## 🚀 Overview

`LeanPromise` is a powerful tool for managing asynchronous operations (such as asset loading, character spawning, network requests, or DataStore calls) in a clean, non-blocking, and readable way. It transforms confusing, nested "callback hell" and fragile polling loops into clean, sequential chains of logic.

The library is architected as a self-contained package:

| Module | Location | Purpose |
| :--- | :--- | :--- |
| `init.luau` | `.../LeanPromise/` | The main entry point and the `Promise` class constructor. This is what you `require`. |
| `PromiseError.luau` | `.../LeanPromise/` | A rich error object used for Promise rejections, providing detailed debug info. |

## 📦 How to Get

Open the [Releases](https://github.com/Distracted-Games/LeanPromise/releases/latest) page on the right side of the screen and either download the Roblox Model containing the module to drag into your Roblox Studio or directly download the source code.

## 🧠 Design Philosophy

This library was built on three core professional principles:

1.  **Asynchronous by Default**  
    All operations that can yield or run concurrently are cleanly encapsulated in a `Promise`. This allows you to write non-blocking code that keeps your game fast and responsive, with clear success (`:andThen`) and failure (`:catch`) paths for every operation.

2.  **Strictly Type-Safe**  
    The entire library is written with `--!strict` and Luau's modern type solver in mind. It features a comprehensive, generic type system providing an unparalleled developer experience with full autocomplete, parameter inference, and compile-time confidence in your asynchronous code.

3.  **Lean and Idiomatic**  
    The API is designed to be clean, intuitive, and aligned with modern Luau best practices. It provides the essential, powerful features of a Promise library without unnecessary bloat or memory overhead, making it easy to learn, maintain, and drop into production codebases.

## 📦 How to Use

The core idea is to wrap a yielding or asynchronous task in a `Promise`. This immediately returns a `Promise` object that you can attach callbacks to, sequence with chained operations, cancel if aborted, or yield for using `:await()`.

### Common Example: Character Setup & Asset Preloading

A common challenge in Roblox development is safely waiting for a player's character to finish spawning and preloading critical visual/audio assets with cancellation support if the player leaves mid-load:

```lua
--!strict
const ContentProvider = game:GetService("ContentProvider")
const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const LeanPromise = require(ReplicatedStorage.Path.To.LeanPromise)

type Promise<T> = LeanPromise.Promise<T>

--[[
	Helper: Wait for a player's Character and HumanoidRootPart without indefinite yielding
]]
local function waitForCharacterRoot(player: Player): Promise<BasePart>
	return LeanPromise.new(function(resolve, reject, onCancel)
		if not player:IsDescendantOf(Players) then
			reject("Player left before character spawned")
			return
		end

		local character = player.Character
		local rootPart = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if rootPart and rootPart:IsA("BasePart") then
			resolve(rootPart)
			return
		end

		local characterAddedConn: RBXScriptConnection? = nil
		local childAddedConn: RBXScriptConnection? = nil

		local function cleanup()
			if characterAddedConn then
				characterAddedConn:Disconnect()
				characterAddedConn = nil
			end
			if childAddedConn then
				childAddedConn:Disconnect()
				childAddedConn = nil
			end
		end

		onCancel(cleanup)

		local function onCharacter(char: Model)
			const existing = char:FindFirstChild("HumanoidRootPart")
			if existing and existing:IsA("BasePart") then
				cleanup()
				resolve(existing)
				return
			end

			childAddedConn = char.ChildAdded:Connect(function(child)
				if child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
					cleanup()
					resolve(child)
				end
			end)
		end

		if character then
			onCharacter(character)
		end

		characterAddedConn = player.CharacterAdded:Connect(onCharacter)
	end) :: Promise<BasePart> -- Due to limitations of the type solverwe need to cast here
end

--[[
	Helper: Preload game assets asynchronously
]]
local function preloadAssets(instances: { Instance }): Promise<nil>
	return LeanPromise.new(function(resolve, reject)
		const success, err = pcall(function()
			ContentProvider:PreloadAsync(instances)
		end)

		if success then
			resolve(nil)
		else
			reject(err)
		end
	end) :: Promise<nil>
end

--[[
	Compose character preparation and asset preloading concurrently using Promise.all
]]
local function preparePlayerForMatch(player: Player, matchAssets: { Instance })
	print(`Preparing {player.Name} for match...`)

	const characterPromise = waitForCharacterRoot(player)
	const preloadPromise = preloadAssets(matchAssets)

	-- Wait for both concurrent tasks or timeout after 10 seconds:
	LeanPromise.race({
		LeanPromise.all({ characterPromise, preloadPromise }),
		LeanPromise.delay(10):andThen(function()
			return LeanPromise.reject("Preparation timed out")
		end),
	})
		:andThen(function()
			print(`{player.Name} is fully loaded and ready to play!`)
		end)
		:catch(function(err)
			warn(`Failed to prepare {player.Name}: {tostring(err)}`)
		end)
end
```

## 🛠️ API Reference

### Core Constructors & Static Utilities

| Function | Description |
| :--- | :--- |
| `LeanPromise.new(executor)` | Creates a new `Promise`. The `executor(resolve, reject, onCancel)` function runs immediately. |
| `LeanPromise.resolve(value)` | Returns a Promise that resolves with `value`. If `value` is already a Promise, it unwraps and adopts its state. |
| `LeanPromise.reject(reason)` | Returns a Promise that rejects with `reason`. |
| `LeanPromise.delay(seconds)` | Returns a Promise that resolves with the elapsed duration after `seconds`. Cancelling it cancels the underlying scheduled task. |
| `LeanPromise.all(promises)` | Returns a Promise that resolves with an array of values when **all** input promises resolve, or rejects immediately when any input rejects (cancelling unshared remaining tasks). |
| `LeanPromise.race(promises)` | Returns a Promise that settles with the first input promise to resolve or reject, cancelling unshared losing tasks. |
| `LeanPromise.is(value)` | Returns `true` if `value` is a `LeanPromise` instance. |

### Instance Methods

| Method | Description |
| :--- | :--- |
| `promise:andThen(onFulfilled, onRejected)` | Chains fulfillment and rejection handlers. Returns a new chained `Promise`. |
| `promise:catch(onRejected)` | Shorthand for `:andThen(nil, onRejected)`. Handles failures and can recover the chain. |
| `promise:finally(onFinally)` | Registers a callback that runs when settled (`Status.Resolved`, `Status.Rejected`, or `Status.Cancelled`). Can return a Promise to hold the chain until settled. |
| `promise:cancel()` | Cancels the Promise and triggers registered `onCancel` hooks, stopping pending work and propagating down the consumer chain. |
| `promise:getStatus()` | Returns the current status string (`"Started"`, `"Resolved"`, `"Rejected"`, or `"Cancelled"`). |
| `promise:await()` | Yields the current thread until the Promise settles. Returns the resolved value(s) or throws on rejection / cancellation. |

### Promise Status Constants

Access settlement statuses via `LeanPromise.Status`:
- `LeanPromise.Status.Started`
- `LeanPromise.Status.Resolved`
- `LeanPromise.Status.Rejected`
- `LeanPromise.Status.Cancelled`

## ✨ Features

- **Clean Asynchronous Chains:** Say goodbye to nested callbacks and fragile polling loops.
- **Robust Error Handling:** Centralized `.catch` error paths preserve custom error objects and include stack traces via `PromiseError`.
- **Parallel & Race Operations:** Easily coordinate concurrent tasks with `LeanPromise.all` and `LeanPromise.race` without leaking unfinished coroutines.
- **Full Cancellation Support:** Abort pending operations and trigger cleanup hooks cleanly across complex consumer chains.
- **Strictly Type-Safe:** Fully generic, `--!strict` compliant, and tested against Luau's modern type solver.

## ⚠️ Important Notes

- **Error Inspection:** Rejections may be wrapped in a `PromiseError` object containing context and stack traces. Use `tostring(err)` or `PromiseError.isKind(err, kind)` to inspect error details.
- **Adoption:** Returning a `Promise` from an `:andThen`, `:catch`, or `:finally` callback automatically unwraps and adopts the state of the returned Promise.
- **Unhandled Rejection Warnings:** Promises that reject without any attached rejection listener will emit a deferred `warn` containing their traceback and reason.

## 📁 Folder Placement

To keep your project organized, I recommend placing the `LeanPromise` package in:

```
ReplicatedStorage/
└── Source/
    └── Libs/
        └── LeanPromise/
            ├── init.luau
            └── PromiseError.luau
```

---

**LeanPromise** is designed to be a foundational tool for any professional Roblox project, enabling you to write complex, high-performance, and maintainable asynchronous code with confidence.
