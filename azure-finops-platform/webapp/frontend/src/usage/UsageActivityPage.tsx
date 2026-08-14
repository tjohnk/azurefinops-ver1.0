import * as React from "react";
import { useEffect, useMemo, useState } from "react";

const stylesheetId = "usage-activity-theme";
if (typeof document !== "undefined" && !document.getElementById(stylesheetId)) {
 const link = document.createElement("link");
 link.id = stylesheetId;
 link.rel = "stylesheet";
 link.href = "./src/usage/usage.css";
 document.head.appendChild(link);
}
const envs=["All","Sandbox","Dev","Staging","Production"];
const tabs=["Overview","Last Activity","Active vs Inactive","Service Adoption","Never Used","90+ Days Inactive",
"Usage Trend","Created","Deleted","Resource Changes","Activity Log","Identities","Human vs Automation",
"Failed Operations","Start / Stop","Deployments","VM Utilization","App Service","Storage","SQL","Health",
"Activity Heatmap","Environment × Service","Usage → Cost"];
const ranges=[["30","30 Days"],["90","90 Days"],["365","365 Days"],["all","All Time"]];
const paths:any={"Overview":"overview","Last Activity":"last-activity","Active vs Inactive":"environment",
"Service Adoption":"adoption","Never Used":"never-used","90+ Days Inactive":"inactive","Usage Trend":"trend",
"Created":"changes","Deleted":"changes","Resource Changes":"changes","Activity Log":"changes",
"Identities":"identities","Human vs Automation":"identities","Failed Operations":"failures",
"Start / Stop":"changes","Deployments":"deployments","VM Utilization":"vm-utilization","App Service":"app-service",
"Storage":"storage","SQL":"sql","Health":"health","Activity Heatmap":"heatmap",
"Environment × Service":"environment-service","Usage → Cost":"usage-cost"};
export default function UsageActivityPage(){
 const [env,setEnv]=useState("All"),[tab,setTab]=useState("Overview"),[range,setRange]=useState("90"),[rows,setRows]=useState<any[]>([]);
 useEffect(()=>{const p=new URLSearchParams(); if(env!=="All")p.set("e",env); if(tab==="Usage Trend")p.set("range",range); const q=p.toString();
 fetch(`/api/usage/${paths[tab]}${q?`?${q}`:""}`).then(r=>r.json()).then(x=>setRows(Array.isArray(x)?x:[]));},[tab,env,range]);
 return <main className="usage"><header><div><small>AZURE ESTATE INTELLIGENCE</small><h1>Usage & Activity</h1>
 <p>Resource adoption, activity, utilization and operational change intelligence.</p></div>
 <div className="filters"><select value={env} onChange={e=>setEnv(e.target.value)}>{envs.map(x=><option key={x}>{x}</option>)}</select>
 {tab==="Usage Trend"?<select value={range} onChange={e=>setRange(e.target.value)}>{ranges.map(x=><option key={x[0]} value={x[0]}>{x[1]}</option>)}</select>:null}</div></header>
 <nav>{tabs.map(x=><button className={x===tab?"on":""} onClick={()=>setTab(x)}>{x}</button>)}</nav>
 {tab==="Overview"?<Overview r={rows[0]}/>:tab==="Usage Trend"?<Trend rows={rows} range={range}/>:<Report title={tab} rows={rows}/>}</main>
}
function Overview({r}:{r:any}){r=r||{};return <><section className="kpis">
 {["TotalResources","ActiveResources","InactiveResources","NeverUsedResources","ActivityEvents","RequestEvents"].map((k)=><article><span>{k.replace("Resources"," Resources")}</span><b>{(r[k]??0).toLocaleString?.()??0}</b></article>)}
 </section><section className="grid"><div className="panel"><h3>Key usage reports</h3>
 {["Service Adoption","Last Activity","90+ Days Inactive","Never Used","Human vs Automation","Usage → Cost"].map(x=><div className="item"><b>{x}</b><span>Open →</span></div>)}</div>
 </section></>}

function Trend({rows,range}:{rows:any[],range:string}){
  // rows expected to be array of points {d: Date|string, a:number, q:number}
  const pts = Array.isArray(rows) && rows.length ? rows.map((p:any)=>({d: p.d? new Date(p.d): new Date(), a: Number(p.a||0), q: Number(p.q||0)})) : [];
  const w = 600, h = 140;
  const step = Math.max(1, Math.floor(pts.length/6));
  const label = (d:Date)=>d.toLocaleDateString();
  const scale = (v:number, max:number)=> Math.round((v/max)*(h-20));
  const maxA = Math.max(1, ...pts.map(p=>p.a));
  const maxQ = Math.max(1, ...pts.map(p=>p.q));
  function line(which:string){
    const max = which==="a"?maxA:maxQ;
    return pts.map((p,i)=>`${Math.round((i/(pts.length-1||1))*w)},${h - scale(which==="a"?p.a:p.q,max)}`).join(" ");
  }
  return <section className="panel report trend"><div className="rh"><h3>Usage Trend</h3><span>{pts.length} points</span></div>{!pts.length?<p>No data returned.</p>:<><svg viewBox={`0 0 ${w} ${h}`} className="trendChart" preserveAspectRatio="none"><polyline points={line("a")} className="lineA" fill="none" stroke="#6cc8ff" strokeWidth={2}/><polyline points={line("q")} className="lineQ" fill="none" stroke="#74b64f" strokeWidth={2}/></svg><div className="trendX">{pts.map((p:any,i:number)=><span key={i} className={i%step===0||i===pts.length-1?"":"hide"}>{label(p.d)}</span>)}</div>
  <div className="chart-note">X-axis: Date (UTC). Y-axis: Activity and Requests (counts).</div>
  <table><thead><tr><th>Period</th><th>Activity</th><th>Requests</th></tr></thead><tbody>{pts.map((p:any,i:number)=><tr key={i}><td>{p.d.toLocaleDateString()}</td><td>{p.a.toLocaleString()}</td><td>{p.q.toLocaleString()}</td></tr>)}</tbody></table></>}</section>
}
function Report({title,rows}:{title:string,rows:any[]}){const cols=rows.length?Object.keys(rows[0]).slice(0,10):[];return <section className="panel report"><div className="rh"><h3>{title}</h3><span>{rows.length} records</span></div>{!rows.length?<p>No data returned.</p>:<table><thead><tr>{cols.map(c=><th>{c}</th>)}</tr></thead><tbody>{rows.map(r=><tr>{cols.map(c=><td>{r[c]==null?"-":String(r[c])}</td>)}</tr>)}</tbody></table>}</section>}
