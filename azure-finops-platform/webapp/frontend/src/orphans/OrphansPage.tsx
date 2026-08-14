
import React,{useEffect,useState} from "react";
import "./orphans.css";

type Row={ResourceId:string;ResourceName:string;ServiceName:string;Environment:string;
AgeDays:number;Cost90D:number;AnnualizedCost:number;Confidence:number;OrphanReason:string;
DependencyStatus?:string;Owner?:string;Recommendation?:string};

export default function OrphansPage(){
 const [env,setEnv]=useState("All"),[summary,setSummary]=useState<any>(),[rows,setRows]=useState<Row[]>([]);
 useEffect(()=>{const q=env==="All"?"":`?environment=${encodeURIComponent(env)}`;
  fetch(`/api/orphans/summary${q}`).then(r=>r.json()).then(x=>setSummary(x[0]));
  fetch(`/api/orphans/top${q}`).then(r=>r.json()).then(setRows);
 },[env]);
 const money=(n:number)=>new Intl.NumberFormat("en-US",{style:"currency",currency:"USD",maximumFractionDigits:1}).format(n);
 return <main className="orphans"><header><div><small>AZURE ESTATE</small><h2>Orphaned Resources</h2><p>Detect, enrich, review and remediate potentially orphaned Azure resources.</p></div>
 <select value={env} onChange={e=>setEnv(e.target.value)}>{["All","Sandbox","Dev","Staging","Production"].map(x=><option key={x}>{x}</option>)}</select></header>
 <section className="cards">{[
 ["Total Orphans",summary?.Total??0],["High Confidence",summary?.HighConfidence??0],
 ["Production",summary?.Production??0],[">90 Days",summary?.Over90Days??0],
 ["90D Cost",money(summary?.Cost90D??0)],["Annualized Potential",money(summary?.PotentialAnnualSaving??0)]
 ].map(x=><article><span>{x[0]}</span><b>{x[1]}</b></article>)}</section>
 <section className="panel"><h3>Top Candidates by Annualized Cost</h3><table><thead><tr>
 <th>Resource</th><th>Service</th><th>Environment</th><th>Age</th><th>90D Cost</th><th>Confidence</th><th>Reason</th><th>Action</th>
 </tr></thead><tbody>{rows.map(r=><tr><td><b>{r.ResourceName}</b><small>{r.ResourceId}</small></td><td>{r.ServiceName}</td>
 <td>{r.Environment}</td><td>{r.AgeDays}d</td><td>{money(r.Cost90D)}</td>
 <td><em className={r.Confidence>=90?"high":"review"}>{r.Confidence}%</em></td>
 <td>{r.OrphanReason.replace(/_/g," ")}</td><td><button>Details</button></td></tr>)}</tbody></table></section>
 <p className="safety">⚠ Detection does not mean safe to delete. Validate dependencies and ownership before remediation.</p>
 </main>
}
