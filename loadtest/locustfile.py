"""Load test of the inference API (bonus "Test de charge").

Run (headless, 60 s, 20 users):
    locust -f loadtest/locustfile.py --host https://<api-fqdn> \
           --headless -u 20 -r 5 -t 60s --csv docs/loadtest/locust
"""

import random

from locust import HttpUser, between, task

REVIEWS = [
    "The battery lasts all day and the screen is gorgeous.",
    "Worst customer service I have ever experienced.",
    "Delivery was fast and the packaging was perfect.",
    "The food was cold and the waiter was rude.",
    "I would definitely recommend this place to my friends.",
    "It broke after two days, total waste of money.",
    "Great value for the price, very happy with it.",
    "The movie was boring and far too long.",
]


class ApiUser(HttpUser):
    wait_time = between(0.1, 0.5)

    @task(10)
    def predict(self):
        batch = random.choices(REVIEWS, k=random.randint(1, 50))  # noqa: S311 - test data, not crypto
        with self.client.post("/predict", json={"texts": batch}, catch_response=True) as resp:
            if resp.status_code != 200 or resp.json().get("count") != len(batch):
                resp.failure(f"unexpected response {resp.status_code}")

    @task(1)
    def health(self):
        self.client.get("/health")
