import React from 'react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { webcrypto } from 'node:crypto';
import { LabelPrintPanel } from './label-print';
import { request } from './api';
vi.mock('qrcode',()=>({default:{toCanvas:vi.fn(async()=>{})}}));
vi.mock('jsbarcode',()=>({default:vi.fn()}));
vi.mock('./api',()=>({request:vi.fn(),getApiBaseUrl:()=> 'https://api.example.test'}));
const token=`header.${btoa(JSON.stringify({id:'staff-1'}))}.signature`;
let localJobs, sent;
beforeEach(()=>{
 sessionStorage.clear();localJobs=[];sent=[];
 vi.stubGlobal('crypto',webcrypto);
 vi.spyOn(HTMLCanvasElement.prototype,'getContext').mockReturnValue({fillRect:vi.fn(),fillText:vi.fn(),drawImage:vi.fn(),measureText:()=>({width:50})});
 vi.spyOn(HTMLCanvasElement.prototype,'toDataURL').mockReturnValue('data:image/png;base64,aW1hZ2U=');
 vi.spyOn(window,'confirm').mockReturnValue(true);
 request.mockImplementation(async path=>path.endsWith('/history')?[]:{id:'p1',trackingId:'D2F1',recipientName:'Recipient',origin:'Omaha',destination:'Lomé',method:'SEA',weightKg:2});
 vi.stubGlobal('fetch',vi.fn(async(url,options)=>{
  sent.push({url,options});let data=url.endsWith('/health')?{ready:true}:url.endsWith('/printers')?['Brother']:localJobs;
  if(options.method==='POST'){const body=JSON.parse(options.body);data={...body,pages:1,status:'QUEUED',source:'WINDOWS_LOCAL_CONNECTOR',deviceTimeMs:Date.now(),message:'Windows accepted the print job.'};delete data.png;delete data.reprint;localJobs=[data];}
  return {ok:true,json:async()=>data};
 }));
});
afterEach(()=>{cleanup();vi.restoreAllMocks();vi.unstubAllGlobals();});
async function open(){
 render(<LabelPrintPanel parcelId="p1" token={token}/>);fireEvent.click(screen.getByRole('button',{name:'Print Label'}));await screen.findByRole('dialog');
 fireEvent.change(screen.getByLabelText('Local connector pairing key'),{target:{value:'local-key'}});fireEvent.click(screen.getByRole('button',{name:'Connect local printer'}));await screen.findByText('Connected to the local Windows connector. Select the actual Brother 4×6 printer queue.');
}
test('explicit local print sends only the local key and syncs an audited queue result',async()=>{
 await open();fireEvent.click(screen.getByRole('button',{name:'Print one label'}));
 await screen.findByText(/Print history synced/);
 const post=sent.find(r=>r.options.method==='POST');expect(post.options.headers.Authorization).toBe('Bearer local-key');expect(post.options.body).not.toContain(token);expect(JSON.parse(post.options.body).ownerId).toBe('api.example.test:staff-1');
 expect(request).toHaveBeenCalledWith('/label-print/history',expect.objectContaining({token,method:'POST',body:expect.stringContaining('QUEUED')}));
 expect(window.confirm).toHaveBeenCalledTimes(1);
});
test('a prior local print requires a reprint reason before another job is sent',async()=>{
 localJobs=[{parcelId:'p1',clientJobId:'earlier',status:'UNKNOWN'}];await open();fireEvent.click(screen.getByRole('button',{name:'Print one label'}));
 await screen.findByRole('alert');expect(screen.getByRole('alert')).toHaveTextContent('enter a reprint reason');expect(sent.filter(r=>r.options.method==='POST')).toHaveLength(0);expect(window.confirm).not.toHaveBeenCalled();
});
