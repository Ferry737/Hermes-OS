class RetryableError(Exception):
    """Transient failure: the task is requeued with backoff."""


class PermanentError(Exception):
    """The task can never succeed as specified: it goes straight to dead."""


class LeaseLost(Exception):
    """Our lease expired and another worker owns the task; our results are discarded."""


class BudgetExceeded(PermanentError):
    """A spend cap would be breached by this call."""
