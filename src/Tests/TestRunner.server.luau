--!strict
local TestSuite = require(script.Parent["LeanPromise.test"])

local totalTests = 0
local passedTests = 0

print("=====================================")
print("  Running tests for Promise Library  ")
print("=====================================")

for testName, testFunction in TestSuite :: { () -> () } do
	totalTests += 1
	local success, err = pcall(function()
        return testFunction
	end)

	if success then
		passedTests += 1
		print(`  [PASS] {testName}`)
	else
		print(`  [FAIL] {testName} - {tostring(err)}`)
	end
end

-- A small delay to allow any final async operations in tests to complete before the summary.
task.wait(1)

print("=====================================")
print(`  Test Summary: {passedTests}/{totalTests} passed.  `)
print("=====================================")
