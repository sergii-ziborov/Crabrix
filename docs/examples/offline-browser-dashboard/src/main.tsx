import {createRoot} from 'react-dom/client';
import {create} from 'zustand';
import {QueryClient, QueryClientProvider, useQuery} from '@tanstack/react-query';
import {z} from 'zod';
import clsx from 'clsx';
import './styles.css';
const Item=z.object({id:z.number().int(),name:z.string(),count:z.number().nonnegative()});
type ItemValue=z.infer<typeof Item>;
const seed: ItemValue[]=z.array(Item).parse([{id:1,name:'Crab',count:2},{id:2,name:'Rust',count:4}]);
const useCounter=create<{n:number,increment:()=>void}>((set)=>({n:0,increment:()=>set(s=>({n:s.n+1}))}));
const client=new QueryClient({defaultOptions:{queries:{retry:false,staleTime:Infinity}}});
function Dashboard(){const {n,increment}=useCounter();const query=useQuery({queryKey:['local-items'],queryFn:async()=>seed});return <main><h1>Offline data dashboard 🦀</h1><p>React + Zustand + TanStack Query + Zod</p><button id="counter" className={clsx('counter',{active:n>0})} onClick={increment}>Count {n}</button><ul>{query.data?.map(item=><li key={item.id}>{item.name}: {item.count+n}</li>)}</ul></main>}
createRoot(document.getElementById('root')!).render(<QueryClientProvider client={client}><Dashboard/></QueryClientProvider>);
