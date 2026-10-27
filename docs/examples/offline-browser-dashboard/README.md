# Offline browser dashboard for Crabrix

An editable browser exercise with React 19.2.0, React DOM 19.2.0, Zustand 5.0.8,
TanStack React Query 5.90.5, Zod 4.1.12 and clsx 2.1.1. It validates local data,
queries an in-memory list and updates shared state when the button is clicked.
No remote API is used. Package licenses remain the original upstream licenses.

1. Open this folder or ZIP in the browser-package update of Crabrix.
2. While connected, open Terminal and run `npm install`.
3. Save the editable project. Original imported dependency modules and licenses
   are retained with `crabrix-web.lock.json`.
4. Disconnect, press Run, or enter `npm run dev` / `npm start`.
5. Edit the heading, stylesheet, validation schema or state update and Run again.

Crabrix maps these supported commands to its local browser builder. It does not
execute Vite, Node, arbitrary scripts or a development server. TypeScript syntax
is transpiled without type checking. Browser storage is temporary; keep source
as the durable copy. See https://crabrix.com/guide/#browser-packages for limits.

This starter's own source is licensed under the accompanying MIT License.
