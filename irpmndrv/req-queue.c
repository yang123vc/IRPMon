
#include <ntifs.h>
#include "preprocessor.h"
#include "allocator.h"
#include "req-queue.h"

#undef DEBUG_TRACE_ENABLED
#define DEBUG_TRACE_ENABLED 0

/************************************************************************/
/*                            GLOBAL VARIABLES                          */
/************************************************************************/

static PKSEMAPHORE _requestListSemaphore = NULL;
static KSPIN_LOCK _requestListLock;
static volatile LONG _requestCount = 0;
static LIST_ENTRY _requestListHead;
static volatile LONG _connected = FALSE;
static IO_REMOVE_LOCK _removeLock;
static ERESOURCE _connectLock;

/************************************************************************/
/*                             HELPER FUNCTIONS                         */
/************************************************************************/

static ULONG _GetRequestSize(PREQUEST_HEADER Header)
{
	ULONG ret = 0;

	switch (Header->Type) {
		case ertIRP:
			ret = sizeof(REQUEST_IRP);
			break;
		case ertIRPCompletion:
			ret = sizeof(REQUEST_IRP_COMPLETION);
			break;
		case ertFastIo:
			ret = sizeof(REQUEST_FASTIO);
			break;
		case ertAddDevice:
			ret = sizeof(REQUEST_ADDDEVICE);
			break;
		case ertDriverUnload:
			ret = sizeof(REQUEST_UNLOAD);
			break;
		case ertStartIo:
			ret = sizeof(REQUEST_UNLOAD);
			break;
	}

	if (ret == 0) {
		DEBUG_ERROR("Invalid request type: %u", Header->Type);
		__debugbreak();
	}

	return ret;
}

static VOID _RequestQueueClear(VOID)
{
	PREQUEST_HEADER req = NULL;
	PREQUEST_HEADER old = NULL;

	req = CONTAINING_RECORD(_requestListHead.Flink, REQUEST_HEADER, Entry);
	while (&req->Entry != &_requestListHead) {
		old = req;
		req = CONTAINING_RECORD(req->Entry.Flink, REQUEST_HEADER, Entry);
		HeapMemoryFree(old);
	}

	_requestCount = 0;

	return;
}

/************************************************************************/
/*                            PUBLIC ROUTINES                           */
/************************************************************************/

NTSTATUS RequestQueueConnect(HANDLE hSemaphore)
{
	NTSTATUS status = STATUS_UNSUCCESSFUL;
	DEBUG_ENTER_FUNCTION("hSemaphore=0x%p", hSemaphore);
	DEBUG_IRQL_LESS_OR_EQUAL(PASSIVE_LEVEL);

	KeEnterCriticalRegion();
	ExAcquireResourceExclusiveLite(&_connectLock, TRUE);
	if (!_connected) {
		IoInitializeRemoveLock(&_removeLock, 0, 0, 0x7fffffff);
		status = IoAcquireRemoveLock(&_removeLock, NULL);
		if (NT_SUCCESS(status)) {
			if (hSemaphore != NULL)
				status = ObReferenceObjectByHandle(hSemaphore, SEMAPHORE_ALL_ACCESS, *ExSemaphoreObjectType, ExGetPreviousMode(), &_requestListSemaphore, NULL);
			
			if (NT_SUCCESS(status)) {
				_connected = TRUE;
				if (_requestListSemaphore != NULL)
					KeReleaseSemaphore(_requestListSemaphore, IO_NO_INCREMENT, _requestCount, FALSE);
			}

			if (!NT_SUCCESS(status))
				_requestListSemaphore = NULL;
		}
	} else status = STATUS_ALREADY_REGISTERED;

	ExReleaseResourceLite(&_connectLock);
	KeLeaveCriticalRegion();

	DEBUG_EXIT_FUNCTION("0x%x", status)
	return status;
}

VOID RequestQueueDisconnect(VOID)
{
	DEBUG_ENTER_FUNCTION_NO_ARGS();
	DEBUG_IRQL_LESS_OR_EQUAL(APC_LEVEL);

	KeEnterCriticalRegion();
	ExAcquireResourceExclusiveLite(&_connectLock, TRUE);
	if (_connected) {		
		IoReleaseRemoveLockAndWait(&_removeLock, NULL);
		if (_requestListSemaphore != NULL) {
			ObDereferenceObject(_requestListSemaphore);
			_requestListSemaphore = NULL;
		}

		_connected = FALSE;
	}

	ExReleaseResourceLite(&_connectLock);
	KeLeaveCriticalRegion();

	DEBUG_EXIT_FUNCTION_VOID();
	return;
}

VOID RequestQueueInsert(PREQUEST_HEADER Header)
{
	KIRQL irql;
	NTSTATUS status = STATUS_UNSUCCESSFUL;
	DEBUG_ENTER_FUNCTION("Header=0x%p", Header);
	DEBUG_IRQL_LESS_OR_EQUAL(DISPATCH_LEVEL);

	if (_connected) {
		status = IoAcquireRemoveLock(&_removeLock, NULL);
		if (NT_SUCCESS(status)) {
			KeAcquireSpinLock(&_requestListLock, &irql);
			InsertTailList(&_requestListHead, &Header->Entry);
			++_requestCount;
			KeReleaseSpinLock(&_requestListLock, irql);
			if (_requestListSemaphore != NULL)
				KeReleaseSemaphore(_requestListSemaphore, IO_NO_INCREMENT, 1, FALSE);
			
			IoReleaseRemoveLock(&_removeLock, NULL);
		}
	} else HeapMemoryFree(Header);

	DEBUG_EXIT_FUNCTION_VOID();
	return;
}

NTSTATUS RequestQueueGet(PREQUEST_HEADER Buffer, PULONG Length)
{
	KIRQL irql;
	ULONG reqSize = 0;
	PREQUEST_HEADER h = NULL;
	NTSTATUS status = STATUS_UNSUCCESSFUL;
	DEBUG_ENTER_FUNCTION("Buffer=0x%p; Length=0x%p", Buffer, Length);
	DEBUG_IRQL_LESS_OR_EQUAL(APC_LEVEL);

	if (_connected) {
		status = IoAcquireRemoveLock(&_removeLock, NULL);
		if (NT_SUCCESS(status)) {
			KeAcquireSpinLock(&_requestListLock, &irql);
			if (!IsListEmpty(&_requestListHead)) {
				h = CONTAINING_RECORD(_requestListHead.Flink, REQUEST_HEADER, Entry);
				reqSize = _GetRequestSize(h);
				if (reqSize <= *Length) {
					RemoveEntryList(&h->Entry);
					--_requestCount;
					memcpy(Buffer, h, reqSize);
					status = STATUS_SUCCESS;
				} else status = STATUS_BUFFER_TOO_SMALL;
			} else status = STATUS_NO_MORE_ENTRIES;

			KeReleaseSpinLock(&_requestListLock, irql);
			*Length = reqSize;
			if (NT_SUCCESS(status)) {
				if (h != NULL)
					HeapMemoryFree(h);
			}

			IoReleaseRemoveLock(&_removeLock, NULL);
		}
	} else status = STATUS_CONNECTION_DISCONNECTED;

	DEBUG_EXIT_FUNCTION("0x%x, *Length=%u", status, *Length);
	return status;
}

/************************************************************************/
/*                     INITIALIZATION AND FINALIZATION                  */
/************************************************************************/

NTSTATUS RequestQueueModuleInit(PDRIVER_OBJECT DriverObject, PVOID Context)
{
	NTSTATUS status = STATUS_UNSUCCESSFUL;
	DEBUG_ENTER_FUNCTION("DriverObject=0x%p; Context=0x%p", DriverObject, Context);

	UNREFERENCED_PARAMETER(DriverObject);
	UNREFERENCED_PARAMETER(Context);
	InitializeListHead(&_requestListHead);
	KeInitializeSpinLock(&_requestListLock);
	IoInitializeRemoveLock(&_removeLock, 0, 0, 0x7fffffff);
	status = ExInitializeResourceLite(&_connectLock);

	DEBUG_EXIT_FUNCTION("0x%x", status);
	return status;
}

VOID RequestQueueModuleFinit(PDRIVER_OBJECT DriverObject, PVOID Context)
{
	DEBUG_ENTER_FUNCTION("DriverObject=0x%p; Context=0x%p", DriverObject, Context);

	_RequestQueueClear();
	ExDeleteResourceLite(&_connectLock);

	DEBUG_EXIT_FUNCTION_VOID();
	return;
}
