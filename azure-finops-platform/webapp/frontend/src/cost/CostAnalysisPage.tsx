
import React,{useEffect,useMemo,useState} from "react";
import "./cost.css";

const environments=["All","Sandbox","Dev","Staging","Production"];
const nav=["Overview","Trend","Environment","Services","Resources","Resource Groups","Applications",
"Business Units","Owners","Unallocated","Anomalies","Budget vs Actual","Forecast","SKU","Region",
"Compute","Storage","Networking","Monitoring","Optimization","Commitments"];

type Row=Record<string,any>;

export default function CostAnalysisPage(){
 const [env,setEnv]=useState("All");
 const [view,setView]=useState("Overview");
 const [data,setData]=useState<Row[]>([]);
 const [loading,setLoading]=useState(false);

 useEffect(()=>{
   setLoading(true);
   const endpoint=endpointFor(view,env);
   fetch(endpoint).then(r=>r.json()).then(x=>setData(Array.isArray(x)?x:[])).finally(()=>setLoading(false));
 },[view,env]);

 const summary=useMemo(()=>view==="Overview" ? data[0] : null,[data,view]);

 return <div className="cost-page">
  <header className="cost-header">
   <div><div className="eyebrow">AZURE ESTATE INTELLIGENCE</div><h1>Cost Analysis</h1>
   <p>Understand where Azure spend is going, what is changing and where action is required.</p></div>
   <select value={env} onChange={e=>setEnv(e.target.value)}>{environments.map(x=><option key={x}>{x}</option>)}</select>
  </header>

  <div className="cost-tabs">{nav.map(x=><button className={view===x?"selected":""} onClick={()=>setView(x)} key={x}>{x}</button>)}</div>

  {loading?<div className="loading">Loading cost data…</div>:view==="Overview"?<Overview summary={summary} data={data}/>:<Report title={view} rows={data}/>}
 </div>
}

function Overview({summary,data}:{summary:any,data:Row[]}){
 const s=summary||{};
 return <div>
  <section className="cost-kpis">
   <Kpi label="90D Cost" value={money(s.Cost90D)}/>
   <Kpi label="Annualized Cost" value={money(s.AnnualizedCost)}/>
   <Kpi label="Resources" value={fmt(s.Resources)}/>
   <Kpi label="Period" value="90 Days"/>
   <Kpi label="Potential Savings" value="Open optimization"/>
   <Kpi label="Environment" value="Selected"/>
  </section>
  <section className="cost-grid">
   <div className="cost-panel"><h3>Cost Analysis Areas</h3>
    <div className="area-grid">{["Environment","Service","Application","Resource Group","Owner","Business Unit","SKU","Region"].map(x=><div><b>{x}</b><span>Drill down →</span></div>)}</div>
   </div>
   <div className="cost-panel"><h3>Recommended Actions</h3>
    <ul><li>Review largest cost drivers</li><li>Investigate unusual cost increases</li><li>Review unallocated spend</li><li>Compare actuals with budget</li><li>Review forecast variance</li></ul>
   </div>
  </section>
 </div>
}

function Report({title,rows}:{title:string,rows:Row[]}){
 const columns=rows.length?Object.keys(rows[0]).slice(0,10):[];
 return <section className="cost-panel report"><div className="report-head"><h3>{title}</h3><span>{rows.length} records</span></div>
   {title==="Environment"&&rows.length?<EnvironmentChart rows={rows}/>:null}
  {!rows.length?<div className="empty">No data returned for this view.</div>:
  <table><thead><tr>{columns.map(c=><th key={c}>{label(c)}</th>)}</tr></thead>
  <tbody>{rows.map((r,i)=><tr key={i}>{columns.map(c=><td key={c}>{formatCell(c,r[c])}</td>)}</tr>)}</tbody></table>}
 </section>
}

function EnvironmentChart({rows}:{rows:Row[]}){
 const chartRows=rows
  .map(r=>({name:String(r.Environment??"Unknown"),value:Number(r.Cost90D??0)}))
  .filter(r=>!Number.isNaN(r.value));
 const max=Math.max(1,...chartRows.map(r=>r.value));
 const ticks=[1,0.75,0.5,0.25,0];
 return <div className="env-chart-wrap">
  <div className="env-axis-left">{ticks.map(t=><span key={t}>{usd(max*t)}</span>)}</div>
  <div className="env-chart">{chartRows.map(r=><div className="env-bar-group" key={r.name}>
   <span className="env-bar-value">{usd(r.value)}</span>
   <div className="env-bar-track"><div className="env-bar-fill" style={{height:`${(r.value/max)*100}%`}} /></div>
   <span className="env-bar-label">{r.name}</span>
  </div>)}</div>
 </div>
}

function Kpi({label,value}:{label:string,value:any}){return <div className="cost-kpi"><span>{label}</span><strong>{value}</strong></div>}
function endpointFor(view:string,env:string){
 const q=env==="All"?"":`?environment=${encodeURIComponent(env)}`;
 const m:any={"Overview":"overview","Trend":"trend","Environment":"environment","Services":"service","Resources":"resource",
 "Resource Groups":"resource-group","Applications":"application","Business Units":"business-unit","Owners":"owner",
 "Unallocated":"unallocated","Anomalies":"anomalies","Budget vs Actual":"budget","Forecast":"forecast","SKU":"sku","Region":"region",
 "Compute":"categories/compute","Storage":"categories/storage","Networking":"categories/networking","Monitoring":"categories/monitoring",
 "Optimization":"../finops/optimization","Commitments":"../finops/commitments"};
 return `/api/cost/${m[view]||"overview"}${q}`;
}
function label(s:string){return s.replace(/_/g," ").replace(/([a-z])([A-Z])/g,"$1 $2")}
function fmt(v:any){return v==null?"-":Number(v).toLocaleString()}
function money(v:any){if(v==null)return "-";return new Intl.NumberFormat("en-US",{style:"currency",currency:"USD",maximumFractionDigits:1}).format(Number(v))}
function usd(v:any){if(v==null)return "-";return new Intl.NumberFormat("en-US",{style:"currency",currency:"USD",maximumFractionDigits:0}).format(Number(v))}
function formatCell(c:string,v:any){if(v==null)return "-";if(c.toLowerCase().includes("cost")||c.toLowerCase().includes("saving")||c.toLowerCase().includes("budget")||c.toLowerCase().includes("actual"))return money(v);if(typeof v==="number")return fmt(v);return String(v)}
