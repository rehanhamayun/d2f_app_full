import {render,screen,within} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {it,expect,vi,afterEach} from 'vitest';
import {CustodyActions} from './custody.jsx';
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json'}});
afterEach(()=>vi.restoreAllMocks());
it('dispatch confirms a separate appointment, receiving warehouse and assigned driver',async()=>{
 const writes=[],saved=vi.fn();vi.stubGlobal('fetch',vi.fn(async(url,options={})=>{if(options.method==='POST'){writes.push(JSON.parse(options.body));return json({status:'PICKUP_SCHEDULED'});}return json(url.includes('drivers')?[{id:'d1',fullName:'Assigned Driver'}]:[{id:'l1',name:'Omaha warehouse',city:'Omaha',country:'United States'}]);}));
 const user=userEvent.setup();render(<CustodyActions parcel={{id:'p1',status:'REQUESTED',deliveryMode:'PICKUP',pickupPreferredAt:new Date(Date.now()+86400000).toISOString(),items:[]}} token="test" onSaved={saved}/>);
 await user.click(screen.getByRole('button',{name:'Schedule pickup & assign driver'}));
 await user.selectOptions(await screen.findByLabelText('Planned receiving warehouse'),'l1');await user.selectOptions(screen.getByLabelText('Assigned pickup driver'),'d1');await user.click(screen.getByLabelText('D2F confirmed this appointment, driver and receiving warehouse with the customer.'));await user.click(screen.getByRole('button',{name:'Confirm pickup appointment'}));
 expect(writes[0]).toMatchObject({locationId:'l1',pickupDriverId:'d1',confirmed:true});expect(writes[0].status).toBeUndefined();expect(writes[0].pickupScheduledAt).toBeTruthy();
});
it('a scheduled pickup never exposes a warehouse receipt action',()=>{
 vi.stubGlobal('fetch',vi.fn(async()=>json([])));render(<CustodyActions parcel={{id:'p1',status:'PICKUP_SCHEDULED',deliveryMode:'PICKUP',items:[]}} token="test" onSaved={vi.fn()}/>);
 expect(screen.queryByRole('button',{name:'Scan & verify warehouse receipt'})).toBeNull();expect(screen.getByText(/assigned driver confirms physical collection/)).toBeInTheDocument();
});
