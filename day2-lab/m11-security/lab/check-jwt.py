import sys, jwt
SECRET = "paybank-lab-secret-do-not-reuse-1"
token = sys.argv[1]
leeway = int(sys.argv[2]) if len(sys.argv) > 2 else 0
try:
    claims = jwt.decode(token, SECRET, algorithms=["HS256"],
                        audience="payment-api",
                        issuer="https://auth.example.com",
                        leeway=leeway)
    print("VALID:", claims)
except jwt.PyJWTError as e:
    print("REJECTED:", type(e).__name__, "-", e)
