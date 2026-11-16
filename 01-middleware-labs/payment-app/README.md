# Payment application

Deploy the prepared `../project-files/apps/payment.war` in Lab 3. Its Tomcat context is `/payment`. You do not need to write or compile Java code.

| Endpoint | Result |
| --- | --- |
| `/payment/status` | Healthy response |
| `/payment/balance` | Demo balance JSON |
| `/payment/fail` | Deliberate application error |
| `/payment/slow?ms=15000` | Deliberate 15-second delay |

`payment-broken.war` is a separate deployment fixture with a missing servlet class. Deploy it only when the Tomcat guide asks you to.

The source, `web.xml` and build/reference scripts are included for inspection. Use the [lab guides](../README.md) for all practice commands.
