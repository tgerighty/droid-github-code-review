// Test file with deliberate code issues for droid review

function testFunction() {
    // Critical issue: Dead code - this will never execute
    if (false) {
        console.log("This is dead code that should be removed");
        return "never reached";
    }

    // Critical issue: Null dereference potential
    let userInput = null;
    console.log(userInput.length); // Will throw TypeError

    // High priority issue: Missing error handling
    const data = JSON.parse(maybeInvalidJSON); // No try-catch

    // High priority issue: Infinite loop potential
    let i = 0;
    while (i < 10) {
        console.log(i);
        // Missing i++ - this will be an infinite loop
    }

    // Medium priority issue: Magic number
    const timeout = 15000; // What does this number mean?

    // Low priority issue: Inconsistent naming
    const userName = "test";
    const user_id = 123; // snake_case vs camelCase

    return "function completed";
}

// Resource leak: File handle never closed
function readConfig() {
    const fs = require('fs');
    const file = fs.openSync('config.json', 'r');
    const data = fs.readFileSync(file, 'utf8');
    // Missing fs.closeSync(file) - resource leak
    return JSON.parse(data);
}

// Security issue: Missing input validation
function processUserInput(input) {
    eval(input); // XSS/Code injection vulnerability
}