import random
import itertools
from typing import Optional, Dict, List, Any  # 注意：将Set改为List


class ResourceAllocator:
    def __init__(self, start: int = 0, end: int = 65535, log: Optional[Any] = None) -> None:
        if start > end:
            raise ValueError("start must be less than or equal to end")

        self.available_resources: List[int] = list(range(start, end + 1))
        self.used_resources: set[int] = set()
        self.business_map: Dict[Any, int] = {}  # business_id -> resource
        self.resource_map: Dict[int, Any] = {}  # resource -> business_id
        self.log = log

    def _log_error(self, message: str) -> None:
        if self.log is not None:
            self.log.error(message)
        else:
            print(f"Error: {message}")

    def _log_debug(self, message: str) -> None:
        if self.log is not None:
            self.log.debug(message)
        else:
            print(f"Debug: {message}")

    def _alloc_resource(self) -> int:

        idx = random.randint(0, len(self.available_resources) - 1)
        self.available_resources[-1], self.available_resources[idx] = self.available_resources[idx], self.available_resources[-1]
        resource = self.available_resources.pop()
        return resource



    def alloc(self, business_id: Any) -> Optional[int]:
        if business_id in self.business_map:
            self._log_error(f"Business ID {business_id} already has resource {self.business_map[business_id]}")
            return None

        if not self.available_resources:
            self._log_error(f"No available resources left for business ID {business_id}")
            return None

        resource = self._alloc_resource()

        self.used_resources.add(resource)
        self.business_map[business_id] = resource
        self.resource_map[resource] = business_id

        # self._log_debug(f"Allocated resource {resource} to business ID {business_id}")
        return resource

    def alloc_id(self) -> Optional[int]:
        if not self.available_resources:
            self._log_error("No available resources left for direct allocation")
            return None

        resource = self._alloc_resource()

        self.used_resources.add(resource)
        # self._log_debug(f"Directly allocated resource {resource}")
        return resource



    def release(self, business_id: Any) -> bool:
        if business_id not in self.business_map:
            self._log_error(f"Business ID {business_id} has no assigned resource")
            return False

        resource = self.business_map.pop(business_id)
        self.resource_map.pop(resource, None)
        self.used_resources.discard(resource)
        self.available_resources.append(resource)

        # self._log_debug(f"Released resource {resource} from business ID {business_id}")
        return True


    def release_id(self, resource: int) -> bool:
        if resource not in self.used_resources:
            self._log_error(f"Resource {resource} is not allocated or already released")
            return False

        if resource in self.resource_map:
            business_id = self.resource_map.pop(resource)
            self.business_map.pop(business_id, None)
            pass
            # self._log_debug(f"Released resource {resource} (previously bound to business ID {business_id})")
        else:
            pass
            # self._log_debug(f"Directly released resource {resource}")

        self.used_resources.remove(resource)
        self.available_resources.append(resource)
        return True

    def get_resource_by_business(self, business_id: Any) -> Optional[int]:
        return self.business_map.get(business_id)

    def get_business_by_resource(self, resource: int) -> Optional[Any]:
        return self.resource_map.get(resource)

    def is_resource_used(self, resource: int) -> bool:
        return resource in self.used_resources

    def get_available_count(self) -> int:
        return len(self.available_resources)

    def get_used_count(self) -> int:
        return len(self.used_resources)


def randbit(y) -> int:
    assert y >= 0
    return random.randint(0, 2**y - 1)


def split_number(num, n) -> List[int]:
    if n == 1:
        return [num]
    else:
        cuts = sorted(random.sample(range(1, num), n - 1))
        parts = [cuts[0]] + [cuts[i] - cuts[i - 1] for i in range(1, len(cuts))] + [num - cuts[-1]]
        return parts

def rand_norm_int(low=0, high=128, mu=64, sigma=20):
    if low == high:
        return low
    while True:
        x = random.gauss(mu, sigma)
        if low <= x <= high:
            return int(round(x))
        
def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)