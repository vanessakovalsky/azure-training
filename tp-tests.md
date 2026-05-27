# TP3 : Conception et mise en œuvre des tests avec Azure

**Durée estimée : 90 minutes**

#### Objectifs
- Créer un plan de test complet
- Implémenter des test cases manuels
- Exécuter les tests et reporter des bugs
- Créer un test de charge simple

---

#### Partie 1 : Créer un plan de test (20 min)

**Scénario :** Application ShopConnect - Sprint 3

**Tâches :**

1. **Créer le test plan**

```
Azure DevOps → Test Plans → + New Test Plan

Name: ShopConnect - Sprint 3 Test Plan
Area Path: ShopConnect
Iteration: Sprint 3
Description: Test plan for Sprint 3 features including authentication and product catalog

[Create]
```

2. **Créer la structure de suites**

```
Test Plan → + New Suite → Static test suite
Name: Authentication Tests
[Create]

Test Plan → + New Suite → Static test suite
Name: Product Catalog Tests
[Create]

Test Plan → + New Suite → Static test suite
Name: Checkout Flow Tests
[Create]
```

3. **Créer des configurations de test**

```
Tests plans → Test Configurations

Configuration 1:
Name: Windows 10 + Chrome
Variables:
  - OS: Windows 10
  - Browser: Chrome 120
  - Resolution: 1920x1080

Configuration 2:
Name: Mobile - Android
Variables:
  - OS: Android 12
  - Browser: Chrome Mobile
  - Device: Samsung Galaxy S21
```

---

#### Partie 2 : Créer des test cases (30 min)

**Suite: Authentication Tests**

**Test Case 1 : Successful Login**

```
Authentication Tests → + New Test Case

Title: User can login with valid credentials

Steps:
┌──┬────────────────────────────────────┬────────────────────────────┐
│# │ Action                              │ Expected Result            │
├──┼────────────────────────────────────┼────────────────────────────┤
│1 │ Navigate to /login                  │ Login page displays        │
│2 │ Enter email: test@example.com       │ Email field accepts input  │
│3 │ Enter password: TestPass123!        │ Password is masked         │
│4 │ Click "Login" button                │ User is redirected to dash │
│5 │ Verify welcome message displays     │ "Welcome, Test User"       │
└──┴────────────────────────────────────┴────────────────────────────┘

Priority: 1 - High
Assigned To: Vous
Area: Authentication
Automation Status: Not Automated

[Save & Close]
```

**Test Case 2 : Login with Invalid Credentials**

```
Title: Login fails with invalid credentials

Steps:
1. Navigate to /login → Login page displays
2. Enter email: invalid@example.com → Email field accepts input
3. Enter password: WrongPassword → Password is masked
4. Click "Login" button → Error message displays
5. Verify error message → "Invalid email or password"
6. Verify user remains on login page → URL is still /login

Priority: 1 - High
```

**Test Case 3 : Password Reset**

```
Title: User can reset password

Steps:
1. Navigate to /login → Login page displays
2. Click "Forgot Password?" link → Password reset page displays
3. Enter email: test@example.com → Email field accepts input
4. Click "Send Reset Link" → Success message displays
5. Check email inbox → Reset email received
6. Click reset link in email → Reset password page opens
7. Enter new password: NewPass123! → Password field accepts
8. Confirm new password: NewPass123! → Confirmation accepted
9. Click "Reset Password" → Success message displays
10. Login with new password → Login successful

Priority: 2 - Medium
```

**Suite: Product Catalog Tests**

**Test Case 4 : Browse Products**

```
Title: User can browse product catalog

Steps:
1. Navigate to /products → Product listing page displays
2. Verify products are displayed → At least 10 products visible
3. Verify product details shown → Name, price, image for each
4. Scroll to bottom → More products load (infinite scroll)
5. Click on a product → Product detail page displays

Priority: 1 - High
```

**Test Case 5 : Search Products**

```
Title: User can search for products

Steps:
1. Navigate to /products → Product listing page displays
2. Enter search term: "laptop" → Search field accepts input
3. Click Search or press Enter → Search results display
4. Verify results relevance → All results contain "laptop"
5. Verify count message → "Showing X results for 'laptop'"
6. Test empty search → Enter "", click Search
7. Verify behavior → All products displayed or empty state

Priority: 2 - Medium
```

**Suite: Checkout Flow Tests**

**Test Case 6 : Add Product to Cart**

```
Title: User can add product to cart

Steps:
1. Navigate to /products → Product listing
2. Click on first product → Product detail page
3. Verify "Add to Cart" button → Button visible and enabled
4. Click "Add to Cart" → Success message displays
5. Verify cart badge updates → Badge shows "1"
6. Click cart icon → Cart page displays
7. Verify product in cart → Product name, price, quantity

Priority: 1 - High
```

**Livrable Partie 2 :**
- 6 test cases créés et sauvegardés
- Test cases liés aux suites appropriées
- Configurations assignées à chaque test case

---

#### Partie 3 : Exécuter les tests et reporter les bugs (25 min)

**Exécuter les tests manuellement**

1. **Lancer le Test Runner**

```
Authentication Tests → Test Case #1 → [Run for web application]
```

2. **Suivre les étapes**

```
Pour chaque step:
1. Exécuter l'action
2. Vérifier le résultat attendu
3. Capturer des screenshots si nécessaire
4. Marquer: Pass ✓ ou Fail ✗
```

3. **Simuler la découverte d'un bug**

```
Test Case #2 (Login Invalid) - Step 5

Expected: "Invalid email or password"
Actual: No error message displays, button just spins forever

[✗ Fail] → Create bug
```

4. **Créer le bug**

```
┌────────────────────────────────────────────────┐
│ New Bug                                        │
├────────────────────────────────────────────────┤
│                                                │
│ Title:                                         │
│ No error message on failed login attempt       │
│                                                │
│ Repro Steps: (Auto-populated from test)       │
│ 1. Navigate to /login                         │
│ 2. Enter invalid@example.com                  │
│ 3. Enter WrongPassword                        │
│ 4. Click Login                                │
│ Result: Button spins indefinitely, no error   │
│                                                │
│ Environment:                                   │
│ Windows 10, Chrome 120                        │
│ Build: 1.2.34                                 │
│                                                │
│ Priority: 2 - High                            │
│ Severity: 2 - High                            │
│                                                │
│ Attachments:                                   │
│ • screenshot-no-error-message.png             │
│                                                │
│ [Save & Close]                                │
└────────────────────────────────────────────────┘
```

5. **Compléter le test run**

```
Une fois tous les steps testés:

Results:
✓ TC-001: Passed
✗ TC-002: Failed (Bug #457 created)
✓ TC-003: Passed
✓ TC-004: Passed
⊘ TC-005: Blocked (Search feature not deployed yet)
✓ TC-006: Passed

[Save & Close]
```

---

#### Partie 4 : Tests de charge basiques (15 min)

**Option 1 : Utiliser K6 (outil simple)**

1. **Installer K6**

```bash
# Windows (via Chocolatey)
choco install k6

# macOS
brew install k6

# Linux
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D00
echo "deb https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

2. **Créer un script de test**

```javascript
// loadtest.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 20 },  // Ramp up to 20 users
    { duration: '1m', target: 20 },   // Stay at 20 users
    { duration: '30s', target: 0 },   // Ramp down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests must complete below 500ms
    http_req_failed: ['rate<0.01'],   // Error rate must be below 1%
  },
};

export default function () {
  // Simulate user journey
  
  // 1. Browse products
  let productsRes = http.get('https://shopconnect-test.com/api/products');
  check(productsRes, {
    'products loaded': (r) => r.status === 200,
    'response time OK': (r) => r.timings.duration < 500,
  });
  
  sleep(2); // Think time
  
  // 2. View product details
  let productId = JSON.parse(productsRes.body)[0].id;
  let productRes = http.get(`https://shopconnect-test.com/api/products/${productId}`);
  check(productRes, {
    'product details loaded': (r) => r.status === 200,
  });
  
  sleep(3); // Think time
  
  // 3. Add to cart
  let addToCartRes = http.post(
    'https://shopconnect-test.com/api/cart',
    JSON.stringify({ productId: productId, quantity: 1 }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(addToCartRes, {
    'added to cart': (r) => r.status === 200 || r.status === 201,
  });
  
  sleep(2); // Think time
}
```

3. **Exécuter le test**

```bash
k6 run loadtest.js
```

4. **Analyser les résultats**

```
          /\      |‾‾| /‾‾/   /‾‾/   
     /\  /  \     |  |/  /   /  /    
    /  \/    \    |     (   /   ‾‾\  
   /          \   |  |\  \ |  (‾)  | 
  / __________ \  |__| \__\ \_____/ .io

  execution: local
     script: loadtest.js
     output: -

  scenarios: (100.00%) 1 scenario, 20 max VUs, 2m30s max duration
           * default: Up to 20 looping VUs for 2m0s over 3 stages

     ✓ products loaded
     ✓ response time OK
     ✓ product details loaded
     ✓ added to cart

     checks.........................: 100.00% ✓ 1200      ✗ 0
     data_received..................: 1.2 MB  10 kB/s
     data_sent......................: 240 kB  2.0 kB/s
     http_req_blocked...............: avg=1.2ms   min=0s      med=0s      max=120ms  
     http_req_connecting............: avg=0.8ms   min=0s      med=0s      max=80ms   
     http_req_duration..............: avg=187ms   min=45ms    med=156ms   max=890ms  
       { expected_response:true }...: avg=187ms   min=45ms    med=156ms   max=890ms  
     ✓ http_req_failed................: 0.00%   ✓ 0         ✗ 1200
     http_req_receiving.............: avg=2.1ms   min=0s      med=1ms     max=45ms   
     http_req_sending...............: avg=0.5ms   min=0s      med=0s      max=12ms   
     http_req_tls_handshaking.......: avg=0s      min=0s      med=0s      max=0s     
     http_req_waiting...............: avg=184ms   min=44ms    med=154ms   max=876ms  
     http_reqs......................: 1200    10/s
     iteration_duration.............: avg=7.2s    min=7.1s    med=7.2s    max=7.9s   
     iterations.....................: 400     3.33/s
     vus............................: 1       min=1       max=20
     vus_max........................: 20      min=20      max=20

running (2m00.0s), 00/20 VUs, 400 complete and 0 interrupted iterations
default ✓ [======================================] 00/20 VUs  2m0s
```

**Analyse :**
- ✅ Tous les checks passent (100%)
- ✅ Aucune erreur HTTP (0%)
- ✅ Temps de réponse moyen: 187ms (< 500ms threshold)
- ✅ P95: 245ms (< 500ms threshold)
- ⚠️ Max: 890ms (à investiguer)

---

#### Livrables attendus

À la fin du TP, vous devez avoir :

✅ Un plan de test avec 3 suites de tests
✅ 6 test cases détaillés avec steps
✅ Au moins 3 tests exécutés avec résultats
✅ Au moins 1 bug créé depuis le Test Runner
✅ Un script de test de charge et ses résultats

---

#### Questions de validation

1. **Quelle est la différence entre Priority et Severity d'un bug ?**
   
2. **Pourquoi est-il important d'inclure les "Repro Steps" détaillés dans un bug ?**
   
3. **Qu'est-ce qu'un "Think Time" dans un test de charge et pourquoi est-il important ?**
   
4. **Comment décidez-vous si un test de charge est réussi ou échoué ?**

---
