import type { PlaygroundDocument } from "./playground-document.ts";

/** Local drafts only hold source. Room secrets and grants are never written here. */
export type StoredDraft = { id: string; name: string; updatedAt: number; document: PlaygroundDocument };

const DATABASE = "crabrix.playground.drafts", STORE = "drafts";
export const KEEP_DRAFTS_KEY = "crabrix.playground.keepDrafts.v1";
export const MAXIMUM_DRAFTS = 32;

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => { request.result.createObjectStore(STORE, { keyPath: "id" }); };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("Browser storage is unavailable."));
  });
}

async function run<T>(mode: IDBTransactionMode, work: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const database = await open();
  try {
    return await new Promise<T>((resolve, reject) => {
      const transaction = database.transaction(STORE, mode), request = work(transaction.objectStore(STORE));
      transaction.oncomplete = () => resolve(request.result);
      transaction.onabort = () => reject(transaction.error ?? new Error("Browser storage refused this draft."));
      transaction.onerror = () => reject(transaction.error ?? new Error("Browser storage refused this draft."));
    });
  } finally { database.close(); }
}

export const listDrafts = async (): Promise<StoredDraft[]> => (await run("readonly", store => store.getAll() as IDBRequest<StoredDraft[]>)).sort((a, b) => b.updatedAt - a.updatedAt);
export const deleteDraft = (id: string): Promise<undefined> => run("readwrite", store => store.delete(id));

export async function saveDraft(id: string, document: PlaygroundDocument): Promise<void> {
  const drafts = await listDrafts();
  if (!drafts.some(draft => draft.id === id) && drafts.length >= MAXIMUM_DRAFTS) throw new Error(`This device already keeps ${MAXIMUM_DRAFTS} drafts. Delete one in Settings.`);
  await run("readwrite", store => store.put({ id, name: document.name, updatedAt: Date.now(), document } satisfies StoredDraft));
}
