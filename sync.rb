#! /usr/bin/env ruby
require "stripe"

require "ougai"
require "pry"

BASE_LOGGER = Ougai::Logger.new($stdout)
BASE_LOGGER.formatter = Ougai::Formatters::Readable.new

def read_entire_set(cursor)
  data = []

  cursor.auto_paging_each { |item| data << item }

  data.flatten
end

def process(friendly_name, stripe_test_sk, stripe_test_pk, stripe_live_sk, stripe_live_pk)
  logger = BASE_LOGGER
  logger.info "Beginning process for building: #{friendly_name}."

  sync_products(logger, stripe_test_sk, stripe_test_pk, stripe_live_sk, stripe_live_pk)
  sync_customers(logger, stripe_test_sk, stripe_test_pk, stripe_live_sk, stripe_live_pk)

  Stripe.api_key = nil
  logger.info "Building processed."
end

def sync_products(logger, stripe_test_sk, stripe_test_pk, stripe_live_sk, stripe_live_pk)
  logger.info "Beginning product sync."

  # NOTE: this is kind of garbage! But this is for a rush.
  Stripe.api_key = stripe_test_sk
  test_products = read_entire_set(Stripe::Product.all)
  logger.info "#{test_products.length} products found in test environment."
  test_plans = read_entire_set(Stripe::Plan.all)
  logger.info "#{test_plans.length} plans found in test environment."

  Stripe.api_key = stripe_live_sk
  live_products = read_entire_set(Stripe::Product.all)
  logger.info "#{live_products.length} products found in live environment."
  live_plans = read_entire_set(Stripe::Plan.all)
  logger.info "#{live_plans.length} plans found in test environment."

  test_products.each do |test_product|
    test_id = test_product.id
    existing_live_product = live_products.find { |lp| lp.metadata["test_id"] == test_id }

    if existing_live_product
      logger.debug "Existing live product for this test product - skipping."
    else
      logger.debug "No live product found. Adding new product to live."
      Stripe::Product.create(
        name: test_product.name,
        type: test_product.type,
        metadata: {
          "test_id" => test_product.id
        }
      )

      logger.debug "Product synced."
    end
  end

  logger.info "Resyncing after product sync..."

  Stripe.api_key = stripe_test_sk
  test_products = read_entire_set(Stripe::Product.all)
  logger.info "#{test_products.length} products found in test environment."
  test_plans = read_entire_set(Stripe::Plan.all)
  logger.info "#{test_plans.length} plans found in test environment."

  Stripe.api_key = stripe_live_sk
  live_products = read_entire_set(Stripe::Product.all)
  logger.info "#{live_products.length} products found in live environment."
  live_plans = read_entire_set(Stripe::Plan.all)
  logger.info "#{live_plans.length} plans found in test environment."

  test_plans.each do |test_plan|
    test_id = test_plan.id
    test_product_id = test_plan.product

    existing_live_plan = live_plans.find { |lp| lp.metadata["test_id"] == test_id }

    if existing_live_plan
      logger.debug "Existing live plan for this test plan - skipping."
    else
      logger.debug "No live plan found. Adding new plan to live."

      live_product = live_products.find { |lp| lp.metadata["test_id"] == test_product_id }

      raise "could not find live product for test product ID #{test_product_id}" if live_product.nil?

      Stripe::Plan.create(
        active: test_plan.active,
        amount: test_plan.amount,
        billing_scheme: test_plan.billing_scheme,
        currency: test_plan.currency,
        interval: test_plan.interval,
        interval_count: test_plan.interval_count,
        metadata: {
          "test_id" => test_id,
          "test_product_id" => test_product_id
        },
        nickname: test_plan.nickname,
        product: live_product.id,
        usage_type: test_plan.usage_type
      )
    end
  end

  logger.info "Product sync completed."
end

def sync_customers(logger, stripe_test_sk, stripe_test_pk, stripe_live_sk, stripe_live_pk)
  logger.info "Beginning customer sync."

  Stripe.api_key = stripe_test_sk
  test_customers = read_entire_set(Stripe::Customer.all)
  logger.info "#{test_customers.length} customers found in test environment."

  Stripe.api_key = stripe_live_sk
  live_customers = read_entire_set(Stripe::Customer.all)
  logger.info "#{live_customers.length} customers found in live environment."

  test_customers.each do |test_customer|
    test_id = test_customer.id
    existing_live_customer = live_customers.find { |lc| lc.metadata["test_id"] == test_id }

    if existing_live_customer
      logger.debug "Existing live customer for this test customer - skipping."
    else
      logger.debug "No live customer found. Adding new customer to live."
      Stripe::Customer.create(
        description: test_customer.description,
        email: test_customer.email,
        invoice_prefix: test_customer.invoice_prefix,
        metadata: {
          "test_id" => test_customer.id
        }
      )

      logger.debug "Customer synced."
    end
  end

  logger.info "Customer sync completed."
end

def main
  require "csv"
  input = ARGV.shift

  if !input
    raise "no input file provided"
  end

  if !File.exist?(input)
    raise "#{input} does not exist"
  end

  CSV.foreach(input).each do |row|
    friendly_name = row[0]
    stripe_test_sk = row[2]
    stripe_test_pk = row[1]
    stripe_live_sk = row[4]
    stripe_live_pk = row[3]

    process(friendly_name, stripe_test_sk, stripe_test_pk, stripe_live_sk, stripe_live_pk)
  end
end

main
