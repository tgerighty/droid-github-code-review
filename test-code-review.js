// Test file with various code issues for droid to review

function buggyFunction(userInput) {
  // Issue: Missing input validation
  if (userInput == null) {
    return "default";
  }
  
  // Issue: Using == instead of ===
  if (userInput == "admin") {
    return true;
  }
  
  // Issue: Unreachable code due to early return
  return false;
  console.log("This will never execute");
  
  // Issue: Potential XSS vulnerability
  var element = document.createElement('div');
  element.innerHTML = userInput; // No sanitization
  document.body.appendChild(element);
}

// Issue: Missing error handling
async function fetchData(url) {
  const response = await fetch(url); // No error handling
  const data = await response.json(); // Could fail if response is not JSON
  return data;
}

// Issue: Infinite loop possibility
function processItems(items) {
  let i = 0;
  while (i < items.length) {
    // Missing i increment - could cause infinite loop
    console.log(items[i]);
    if (items[i] === "skip") {
      continue;
    }
    i++;
  }
}

// Issue: SQL injection vulnerability (pseudo-code)
function getUserData(userId) {
  // String concatenation in SQL query - vulnerable to injection
  const query = "SELECT * FROM users WHERE id = " + userId;
  return database.query(query);
}

// Issue: Memory leak - event listener not removed
function setupButton() {
  const button = document.getElementById('myButton');
  button.addEventListener('click', function() {
    console.log('Button clicked');
  });
  // No cleanup mechanism for event listener
}

// Issue: Off-by-one error in array access
function getLastElement(arr) {
  return arr[arr.length]; // Should be arr.length - 1
}

// Issue: Async/await mistake
async function processMultiple() {
  const results = [];
  const promises = [fetchData('/api/1'), fetchData('/api/2'), fetchData('/api/3')];
  
  // Issue: Not awaiting promises correctly
  promises.forEach(async (promise) => {
    const result = await promise;
    results.push(result);
  });
  
  return results; // Returns before all promises complete
}
