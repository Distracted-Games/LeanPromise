# LeanPromise

A modern, robust, and strictly-typed Promise implementation for Luau. This library is a complete, feature-complete refactor of the popular `Promise.lua` library by evaera, architected to align with modern Luau idioms and a professional, type-safe workflow.

## 🚀 Overview

`LeanPromise` is a powerful tool for managing asynchronous operations (like DataStore calls or asset loading) in a clean, non-blocking, and readable way. It transforms confusing, nested "callback hell" into clean, sequential chains of logic.

The library is architected as a self-contained package:

| Module | Location | Purpose |
| :--- | :--- | :--- |
| `init.luau` | `.../LeanPromise/` | The main entry point and the `Promise` class constructor. This is what you `require`. |
| `PromiseError.luau` | `.../LeanPromise/` | A rich error object used for Promise rejections, providing detailed debug info. |

## 📦 How to Get

Open the [Releases](https://github.com/Distracted-Games/LeanPromise/releases/latest) page on the right side of the screen and either download the Roblox Model containing the module or directly download the source code.

## 🧠 Design Philosophy

This library was built on three core professional principles:

1.  **Asynchronous by Default**  
    All operations that can yield are wrapped in a `Promise`. This allows you to write non-blocking code that keeps your game fast and responsive, with clear success (`:andThen`) and failure (`:catch`) paths for every operation.

2.  **Strictly Type-Safe**  
    The entire library is written with `--!strict` and features a comprehensive, generic type system. This provides an unparalleled developer experience with full autocomplete, error checking, and confidence in your asynchronous code.

3.  **Lean and Idiomatic**  
    The API is designed to be clean, intuitive, and aligned with modern Luau best practices. It provides the essential, powerful features of a Promise library without unnecessary bloat, making it easy to learn and maintain.

## 📦 How to Use

The core idea is to wrap a yielding function in a `Promise`. This immediately returns a `Promise` object that you can attach callbacks to, allowing your script to continue running without lag.

### Basic Example: Wrapping a DataStore Call

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local LeanPromise = require(ReplicatedStorage.Source.Libs.LeanPromise)

local playerData = DataStoreService:GetDataStore("PlayerData")

local function getDataAsync(key: string): LeanPromise.Promise<any>
	return LeanPromise.new(function(resolve, reject)
		local success, result = pcall(function()
			return playerData:GetAsync(key)
		end)

		if success then
			resolve(result) -- The promise succeeded.
		else
			reject(result) -- The promise failed.
		end
	end)
end

-- Now, consume the promise:
print("Requesting data...")
getDataAsync("Player_123")
	:andThen(function(data)
		print(`Data loaded successfully: {data}`)
	end)
	:catch(function(errorMessage)
		warn(`Error loading data: {errorMessage}`)
	end)

print("This message prints immediately, without waiting for the DataStore!")
```

## 🛠️ API Reference

### Core Constructor
| Function | Description |
| :--- | :--- |
| `LeanPromise.new(executor)` | Creates a new `Promise`. The `executor` function is given `resolve` and `reject` callbacks. |

### Key Instance Methods
| Method | Description |
| :--- | :--- |
| `promise:andThen(onFulfilled, onRejected)` | Chains onto a promise. `onFulfilled` runs on success, `onRejected` runs on failure. |
| `promise:catch(onRejected)` | Shorthand for handling only the failure case of a promise. |
| `promise:finally(onFinally)` | Registers a function to run when the promise settles, regardless of success or failure. |
| `promise:cancel()` | Cancels a promise if it is still pending. |
| `promise:await()` | Yields the current thread until the promise is settled. |

### Static Utility Functions
| Function | Description |
| :--- | :--- |
| `LeanPromise.all(promises)` | Returns a new promise that resolves when **all** promises in a table have resolved. |
| `LeanPromise.race(promises)` | Returns a new promise that resolves as soon as the **first** promise in a table resolves. |
| `LeanPromise.resolve(value)` | Creates a new promise that is already automatically resolved with the given value. |
| `LeanPromise.reject(reason)` | Creates a new promise that is already automatically rejected with the given reason. |

## ✨ Features
- **Clean Asynchronous Chains:** Say goodbye to nested callbacks.
- **Robust Error Handling:** A centralized `.catch` makes handling failures trivial.
- **Parallel Operations:** Easily run multiple async tasks at once with `LeanPromise.all`.
- **Full Cancellation Support:** Abort pending operations to prevent memory leaks and unnecessary work.
- **Strictly Type-Safe:** Fully generic and `--!strict` compliant for a professional workflow.

## ⚠️ Important Notes
- **Error Handling:** When using `.catch`, the rejection value may be a `PromiseError` object. To ensure it's a string for printing, use `tostring(err)`.
- **Chaining:** If you return a new `Promise` from within an `.andThen` or `.catch` handler, the chain will intelligently wait for it to settle before continuing, allowing you to chain additional `.andThen` or `.catch` hunadlers. Also used for `.finally` handler.

## 📁 Folder Placement
To keep your project organized, we recommend placing the `LeanPromise` package in:

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
