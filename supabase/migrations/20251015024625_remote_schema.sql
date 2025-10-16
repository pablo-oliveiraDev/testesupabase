create sequence "public"."itens_pedido_id_seq";

create sequence "public"."pedidos_id_seq";

create sequence "public"."produtos_id_seq";

create table "public"."clientes" (
    "id" uuid not null,
    "nome" character varying(255) not null,
    "email" character varying(255) not null,
    "telefone" character varying(20),
    "data_cadastro" timestamp with time zone default now()
);


alter table "public"."clientes" enable row level security;

create table "public"."itens_pedido" (
    "id" bigint not null default nextval('itens_pedido_id_seq'::regclass),
    "pedido_id" bigint not null,
    "produto_id" bigint not null,
    "quantidade" integer not null,
    "preco_unitario" numeric(10,2) not null
);


alter table "public"."itens_pedido" enable row level security;

create table "public"."pedidos" (
    "id" bigint not null default nextval('pedidos_id_seq'::regclass),
    "cliente_id" uuid not null,
    "data_pedido" timestamp with time zone default now(),
    "status" character varying(50) not null default 'Pendente'::character varying,
    "total" numeric(10,2) default 0.00,
    "endereco_envio" text
);


alter table "public"."pedidos" enable row level security;

create table "public"."produtos" (
    "id" bigint not null default nextval('produtos_id_seq'::regclass),
    "nome" character varying(255) not null,
    "descricao" text,
    "preco" numeric(10,2) not null,
    "estoque" integer not null,
    "ativo" boolean default true,
    "data_criacao" timestamp with time zone default now()
);


alter table "public"."produtos" enable row level security;

alter sequence "public"."itens_pedido_id_seq" owned by "public"."itens_pedido"."id";

alter sequence "public"."pedidos_id_seq" owned by "public"."pedidos"."id";

alter sequence "public"."produtos_id_seq" owned by "public"."produtos"."id";

CREATE UNIQUE INDEX clientes_email_key ON public.clientes USING btree (email);

CREATE UNIQUE INDEX clientes_pkey ON public.clientes USING btree (id);

CREATE INDEX idx_itens_pedido_pedido_id ON public.itens_pedido USING btree (pedido_id);

CREATE INDEX idx_itens_pedido_produto_id ON public.itens_pedido USING btree (produto_id);

CREATE INDEX idx_pedidos_cliente_id ON public.pedidos USING btree (cliente_id);

CREATE UNIQUE INDEX itens_pedido_pkey ON public.itens_pedido USING btree (id);

CREATE UNIQUE INDEX pedidos_pkey ON public.pedidos USING btree (id);

CREATE UNIQUE INDEX produtos_pkey ON public.produtos USING btree (id);

CREATE UNIQUE INDEX uk_pedido_produto ON public.itens_pedido USING btree (pedido_id, produto_id);

alter table "public"."clientes" add constraint "clientes_pkey" PRIMARY KEY using index "clientes_pkey";

alter table "public"."itens_pedido" add constraint "itens_pedido_pkey" PRIMARY KEY using index "itens_pedido_pkey";

alter table "public"."pedidos" add constraint "pedidos_pkey" PRIMARY KEY using index "pedidos_pkey";

alter table "public"."produtos" add constraint "produtos_pkey" PRIMARY KEY using index "produtos_pkey";

alter table "public"."clientes" add constraint "clientes_email_key" UNIQUE using index "clientes_email_key";

alter table "public"."clientes" add constraint "clientes_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."clientes" validate constraint "clientes_id_fkey";

alter table "public"."itens_pedido" add constraint "itens_pedido_pedido_id_fkey" FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE CASCADE not valid;

alter table "public"."itens_pedido" validate constraint "itens_pedido_pedido_id_fkey";

alter table "public"."itens_pedido" add constraint "itens_pedido_produto_id_fkey" FOREIGN KEY (produto_id) REFERENCES produtos(id) ON DELETE RESTRICT not valid;

alter table "public"."itens_pedido" validate constraint "itens_pedido_produto_id_fkey";

alter table "public"."itens_pedido" add constraint "itens_pedido_quantidade_check" CHECK ((quantidade > 0)) not valid;

alter table "public"."itens_pedido" validate constraint "itens_pedido_quantidade_check";

alter table "public"."itens_pedido" add constraint "uk_pedido_produto" UNIQUE using index "uk_pedido_produto";

alter table "public"."pedidos" add constraint "pedidos_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE CASCADE not valid;

alter table "public"."pedidos" validate constraint "pedidos_cliente_id_fkey";

alter table "public"."produtos" add constraint "produtos_estoque_check" CHECK ((estoque >= 0)) not valid;

alter table "public"."produtos" validate constraint "produtos_estoque_check";

alter table "public"."produtos" add constraint "produtos_preco_check" CHECK ((preco >= (0)::numeric)) not valid;

alter table "public"."produtos" validate constraint "produtos_preco_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.atualizar_status_pedido(pedido_id_param bigint, novo_status character varying)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    UPDATE pedidos
    SET status = novo_status
    WHERE id = pedido_id_param;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calcular_total_pedido(pedido_id_param bigint)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    total_calculado NUMERIC(10, 2);
BEGIN
    SELECT COALESCE(SUM(quantidade * preco_unitario), 0)
    INTO total_calculado
    FROM itens_pedido
    WHERE pedido_id = pedido_id_param;

    -- Atualiza o campo 'total' na tabela 'pedidos'
    UPDATE pedidos
    SET total = total_calculado
    WHERE id = pedido_id_param;

    RETURN total_calculado;
END;
$function$
;

create or replace view "public"."detalhes_pedidos_cliente" as  SELECT p.id AS pedido_id,
    p.cliente_id,
    p.data_pedido,
    p.status,
    p.total AS valor_total_pedido,
    c.nome AS nome_cliente,
    ip.quantidade,
    ip.preco_unitario AS preco_unitario_no_pedido,
    pr.nome AS nome_produto,
    pr.preco AS preco_atual_produto
   FROM (((pedidos p
     JOIN clientes c ON ((p.cliente_id = c.id)))
     JOIN itens_pedido ip ON ((p.id = ip.pedido_id)))
     JOIN produtos pr ON ((ip.produto_id = pr.id)));


CREATE OR REPLACE FUNCTION public.trigger_recalcular_total()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Determina o ID do pedido a ser recalculado
    IF TG_OP = 'DELETE' THEN
        PERFORM calcular_total_pedido(OLD.pedido_id);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' OR TG_OP = 'INSERT' THEN
        PERFORM calcular_total_pedido(NEW.pedido_id);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$function$
;

create policy "Clientes so podem ver/atualizar seus proprios dados"
on "public"."clientes"
as permissive
for all
to public
using ((auth.uid() = id))
with check ((auth.uid() = id));


create policy "Clientes so podem ver itens de seus proprios pedidos"
on "public"."itens_pedido"
as permissive
for select
to public
using ((EXISTS ( SELECT 1
   FROM pedidos
  WHERE ((pedidos.id = itens_pedido.pedido_id) AND (pedidos.cliente_id = auth.uid())))));


create policy "Permitir insercao de itens_pedido"
on "public"."itens_pedido"
as permissive
for insert
to public
with check ((EXISTS ( SELECT 1
   FROM pedidos
  WHERE ((pedidos.id = itens_pedido.pedido_id) AND (pedidos.cliente_id = auth.uid()) AND ((pedidos.status)::text = 'Pendente'::text)))));


create policy "Clientes so podem inserir pedidos para si mesmos"
on "public"."pedidos"
as permissive
for insert
to public
with check ((auth.uid() = cliente_id));


create policy "Clientes so podem ver seus proprios pedidos"
on "public"."pedidos"
as permissive
for select
to public
using ((auth.uid() = cliente_id));


create policy "Produtos Ativos sao publicos para leitura"
on "public"."produtos"
as permissive
for select
to public
using ((ativo = true));


CREATE TRIGGER recalcular_total_pedido_trigger AFTER INSERT OR DELETE OR UPDATE ON public.itens_pedido FOR EACH ROW EXECUTE FUNCTION trigger_recalcular_total();



