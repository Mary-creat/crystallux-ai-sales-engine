-- Crystallux Clients Table
-- Multi-client Calendly link management and billing configuration

CREATE TABLE IF NOT EXISTS clients (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  client_name TEXT NOT NULL,
  industry TEXT NOT NULL,
  product_type TEXT,
  calendly_link TEXT,
  notification_email TEXT,
  phone TEXT,
  city TEXT,
  active BOOLEAN DEFAULT true,
  stripe_account_id TEXT,
  fee_per_booking DECIMAL,
  monthly_retainer DECIMAL,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Seed first client: Blonai Moving Company
INSERT INTO clients (
  client_name,
  industry,
  product_type,
  calendly_link,
  notification_email,
  city,
  active,
  fee_per_booking,
  monthly_retainer,
  notes
) VALUES (
  'Blonai Moving Company',
  'moving_services',
  'moving_services',
  'https://calendly.com/adesholaakintunde/free-moving-quote-toronto-gta',
  'akintundebowale@gmail.com',
  'Toronto GTA',
  true,
  150.00,
  500.00,
  'First Crystallux client. Serves Toronto GTA area.'
);

-- Enable RLS on clients table
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access to clients"
ON clients FOR ALL TO service_role
USING (true) WITH CHECK (true);
