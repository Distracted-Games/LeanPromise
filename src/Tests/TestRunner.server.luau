--!strict
const TestSuite = require("./LeanPromise.test")

local testNames: { string } = {}
for testName, testFn in TestSuite :: { [string]: any } do
	if typeof(testFn) == "function" then
		table.insert(testNames, testName)
	end
end
table.sort(testNames)

local totalTests = 0
local passedTests = 0

print("=====================================")
print("  Running tests for LeanPromise      ")
print("=====================================")

for _, testName in testNames do
	totalTests += 1
	const testFunction = (TestSuite :: { [string]: () -> () })[testName]
	const success, err = pcall(testFunction)

	if success then
		passedTests += 1
		print(`  [PASS] {testName}`)
	else
		warn(`  [FAIL] {testName} - {tostring(err)}`)
	end
end

print("=====================================")
print(`  Test Summary: {passedTests}/{totalTests} passed.  `)
print("=====================================")
