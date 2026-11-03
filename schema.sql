-- Run this whole file once in Supabase: SQL Editor > New query > Run

create table profiles(id uuid primary key references auth.users on delete cascade, name text, phone text, role text not null default 'patient', created_at timestamptz default now());
create table tests(id uuid primary key default gen_random_uuid(), name text not null, cat text default 'Other', price numeric default 0);
create table bookings(id uuid primary key default gen_random_uuid(), code text, user_id uuid references auth.users on delete cascade, patient_name text, phone text, age text, gender text, visit_date date, visit_time text, note text, tests jsonb, total numeric default 0, status text default 'Pending', paid boolean default false, paid_at timestamptz, report_path text, created_at timestamptz default now());

create function is_staff() returns boolean language sql security definer set search_path=public as $$ select exists(select 1 from profiles where id=auth.uid() and role='staff') $$;

create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into profiles(id,name,phone) values(new.id,new.raw_user_meta_data->>'name',new.raw_user_meta_data->>'phone'); return new; end $$;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();

alter table profiles enable row level security;
alter table tests enable row level security;
alter table bookings enable row level security;

create policy "profile read" on profiles for select using (id=auth.uid() or is_staff());
create policy "tests read" on tests for select using (true);
create policy "tests write" on tests for all using (is_staff()) with check (is_staff());
create policy "booking read" on bookings for select using (user_id=auth.uid() or is_staff());
create policy "booking insert" on bookings for insert with check (user_id=auth.uid());
create policy "booking staff update" on bookings for update using (is_staff());
create policy "booking staff delete" on bookings for delete using (is_staff());

-- private bucket for reports. Files live at <patient user id>/<file>
insert into storage.buckets(id,name,public) values('reports','reports',false);
create policy "reports read" on storage.objects for select using (bucket_id='reports' and (is_staff() or (storage.foldername(name))[1]=auth.uid()::text));
create policy "reports upload" on storage.objects for insert with check (bucket_id='reports' and is_staff());
create policy "reports update" on storage.objects for update using (bucket_id='reports' and is_staff());
create policy "reports delete" on storage.objects for delete using (bucket_id='reports' and is_staff());

-- live notifications
alter publication supabase_realtime add table bookings;

insert into tests(name,cat,price) values
('Complete Blood Count (CBC)','Blood',400),('ESR','Blood',200),('Blood Group','Blood',200),('Malaria Parasite (MP)','Blood',350),('Typhoid (Widal)','Blood',500),('Dengue NS1','Blood',1500),
('Blood Sugar Fasting','Diabetes',150),('Blood Sugar Random','Diabetes',150),('HbA1c','Diabetes',900),
('Lipid Profile','Heart',1200),('CRP','Heart',700),
('Liver Function Test (LFT)','Organ',1100),('Renal Function Test (RFT)','Organ',1000),('Uric Acid','Organ',300),
('Thyroid TSH','Hormone',800),('Vitamin D','Vitamins',2500),('Vitamin B12','Vitamins',1800),
('Hepatitis B (HBsAg)','Infection',600),('Hepatitis C (Anti-HCV)','Infection',900),
('Urine Routine (R/E)','Urine',250),('Pregnancy Test','Urine',300);

-- AFTER you sign up in the app with your own email, make yourself staff (change the email):
-- update profiles set role='staff' where id=(select id from auth.users where email='you@example.com');

-- ===== Background push notifications (staff phones) =====
create table device_tokens(token text primary key, user_id uuid references auth.users on delete cascade, updated_at timestamptz default now());
alter table device_tokens enable row level security;
create policy "own tokens" on device_tokens for all using (user_id=auth.uid()) with check (user_id=auth.uid());
-- Then in Supabase: Database > Webhooks > Create: table bookings, event INSERT, type Supabase Edge Function, function notify-staff
