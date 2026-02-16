import time
import logging
from django.http import JsonResponse
from django.core.cache import cache

logger = logging.getLogger(__name__)

CACHE_KEY = 'menu_items'
CACHE_TIME = 10  # seconds

# Simple endpoint to simulate fetching menu items; cache is shared across workers via Redis
def menu_views(request):
    # Try shared cache (Redis) first
    cached = cache.get(CACHE_KEY)
    if cached is not None:
        out = dict(cached)
        out['from_cache'] = True
        return JsonResponse(out)

    # log request
    logger.info(f"Request received: {request.method} {request.path} from {request.META.get('REMOTE_ADDR')}")
    print(f"[MENU] Request: {request.method} {request.path}")

    now = time.time()
    items = ["Burger", "Pizza", "Salad", "Sushi", "Pasta"]
    response_data = {
        'items': items,
        'served_at': now,
        'from_cache': False,
    }

    # since redis is shared across workers, we can use the cache.set method to set the value in the cache
    cache.set(CACHE_KEY, response_data, timeout=CACHE_TIME)

    return JsonResponse(response_data)

