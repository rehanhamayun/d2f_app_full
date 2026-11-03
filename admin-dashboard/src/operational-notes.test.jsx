import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { vi, it, expect } from 'vitest';
import { useState } from 'react';
import { OperationalNoteField, OperationalNotes } from './operational-notes.jsx';
import { StructuredAddress } from './structured-address.jsx';
const response=data=>new Response(JSON.stringify(data),{headers:{'Content-Type':'application/json'}});
it('standard notes keep extra details separate and custom notes require explicit Other selection',async()=>{
 const changed=vi.fn(),paths=[];
 vi.stubGlobal('fetch',vi.fn(async url=>{paths.push(url);return response([{id:'t1',status:'PROCESSING',message:'Parcel stored securely awaiting shipment.'}]);}));
 render(<OperationalNoteField token="test" status="PROCESSING" serviceType="SEA" onChange={changed}/>);const user=userEvent.setup();
 await screen.findByRole('option',{name:'Parcel stored securely awaiting shipment.'});
 expect(paths[0]).toContain('status=PROCESSING&serviceType=SEA');expect(screen.queryByRole('textbox')).toBeNull();
 await user.selectOptions(screen.getByLabelText('Operational message'),'t1');await user.type(screen.getByLabelText('Add Additional Details (optional)'),'Shelf B4');
 expect(changed.mock.calls.at(-1)[0]).toEqual({noteTemplateId:'t1',additionalDetails:'Shelf B4'});
 await user.selectOptions(screen.getByLabelText('Operational message'),'OTHER');expect(screen.getByLabelText('Custom operational message')).toBeRequired();
 await user.type(screen.getByLabelText('Custom operational message'),'Repacking required.');expect(changed.mock.calls.at(-1)[0]).toEqual({customMessage:'Repacking required.'});
});
it('admin can deactivate and reorder a message while existing history is untouched',async()=>{
 let row={id:'t1',status:'RECEIVED',serviceType:'ALL',message:'Parcel received; inspection pending.',position:4,isActive:true};const writes=[];
 vi.stubGlobal('fetch',vi.fn(async(url,options={})=>{if(options.method==='PATCH'){const data=JSON.parse(options.body);writes.push({url,data});row={...row,...data};return response(row);}return response([row]);}));
 render(<OperationalNotes token="test" notify={vi.fn()} refreshKey={0}/>);const user=userEvent.setup();await user.click(await screen.findByRole('button',{name:'Edit',exact:true}));
 await user.clear(screen.getByLabelText('Display order'));await user.type(screen.getByLabelText('Display order'),'2');await user.click(screen.getByLabelText('Active'));await user.click(screen.getByRole('button',{name:'Save message'}));
 await waitFor(()=>expect(writes).toHaveLength(1));expect(writes[0].url).toContain('/operational-notes/t1');expect(writes[0].data).toMatchObject({position:2,isActive:false,message:'Parcel received; inspection pending.'});expect(await screen.findByText('Inactive')).toBeInTheDocument();
});
it('US address requires an actual state and ZIP before emitting a complete formatted address',async()=>{
 const changed=vi.fn();function Form(){const [value,setValue]=useState('');return <StructuredAddress label="Delivery address" required value={value} onChange={v=>{setValue(v);changed(v);}}/>;}
 render(<Form/>);const user=userEvent.setup();await user.type(screen.getByLabelText('Street address'),'1234 Main Street');await user.type(screen.getByLabelText('City'),'Omaha');await user.type(screen.getByLabelText('ZIP code'),'6810');expect(changed.mock.calls.at(-1)[0]).toBe('');
 await user.type(screen.getByLabelText('ZIP code'),'4');await user.selectOptions(screen.getByLabelText('State'),'NE');expect(changed.mock.calls.at(-1)[0]).toBe('1234 Main Street\nOmaha, NE 68104\nUnited States');expect(screen.getByLabelText('Country')).toHaveAttribute('readonly');
});
