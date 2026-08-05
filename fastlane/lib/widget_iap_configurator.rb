require "bigdecimal"
require "date"

module TokenWatchFastlane
  # Creates and verifies the one-time purchase that unlocks TokenWatch widgets.
  class WidgetIAPConfigurator
    PRODUCT_ID = "com.xiaoao.tokenwatch.widgets.lifetime".freeze
    REFERENCE_NAME = "All Widgets Lifetime".freeze
    PURCHASE_TYPE = "NON_CONSUMABLE".freeze
    BASE_TERRITORY = "USA".freeze
    BASE_PRICE = BigDecimal("2.99")
    CHINA_TERRITORY = "CHN".freeze
    LOCALIZATIONS = {
      "en-US" => {
        name: "Unlock All Widgets",
        description: "Unlock all 7 desktop widgets permanently."
      },
      "zh-Hans" => {
        name: "解锁全部桌面小组件",
        description: "一次购买，永久解锁全部 7 款桌面小组件。"
      }
    }.freeze

    class Error < StandardError; end

    def initialize(client:, app_id:, logger:)
      @client = client
      @app_id = app_id
      @logger = logger
    end

    # Reads the current product state and reports the immutable creation plan.
    def plan
      purchase = find_purchase
      if purchase
        validate_purchase!(purchase)
        reconcile_purchase(purchase, write: false)
        @logger.message("内购项目已存在，将复用：#{PRODUCT_ID} (#{purchase.fetch('id')})")
      else
        app_availability
        @logger.message("计划创建非消耗型内购：#{PRODUCT_ID}")
      end

      {
        exists: !purchase.nil?,
        product_id: PRODUCT_ID,
        reference_name: REFERENCE_NAME,
        purchase_type: PURCHASE_TYPE,
        base_territory: BASE_TERRITORY,
        base_price: format_price(BASE_PRICE)
      }
    end

    # Creates missing resources, validates existing ones, and returns verified store data.
    def configure
      purchase = ensure_purchase
      # Validate every existing child resource before making the first dependent write.
      reconcile_purchase(purchase, write: false)
      reconciliation = reconcile_purchase(purchase, write: true)
      schedule = reconciliation.fetch(:schedule)
      territory_count = reconciliation.fetch(:territory_count)

      verified_purchase = find_purchase
      validate_purchase!(verified_purchase)
      china_price = automatic_price(schedule.fetch("id"), CHINA_TERRITORY)

      {
        id: verified_purchase.fetch("id"),
        product_id: PRODUCT_ID,
        reference_name: REFERENCE_NAME,
        purchase_type: PURCHASE_TYPE,
        state: verified_purchase.dig("attributes", "state"),
        base_territory: BASE_TERRITORY,
        base_price: format_price(BASE_PRICE),
        china_price: china_price,
        localizations: LOCALIZATIONS.keys,
        territory_count: territory_count
      }
    end

    private

    def find_purchase
      purchases = @client.get_all(
        "/v1/apps/#{@app_id}/inAppPurchasesV2",
        query: {
          "filter[productId]" => PRODUCT_ID,
          "limit" => 200
        }
      )
      raise Error, "同一 Product ID 返回了多个内购项目：#{PRODUCT_ID}" if purchases.length > 1

      purchases.first
    end

    def ensure_purchase
      purchase = find_purchase
      if purchase
        validate_purchase!(purchase)
        @logger.message("复用现有内购项目：#{PRODUCT_ID} (#{purchase.fetch('id')})")
        return purchase
      end

      @logger.message("正在创建非消耗型内购：#{PRODUCT_ID}")
      response = @client.post(
        "/v2/inAppPurchases",
        body: {
          data: {
            type: "inAppPurchases",
            attributes: {
              name: REFERENCE_NAME,
              productId: PRODUCT_ID,
              inAppPurchaseType: PURCHASE_TYPE,
              familySharable: false
            },
            relationships: {
              app: {
                data: { type: "apps", id: @app_id }
              }
            }
          }
        }
      )
      response.fetch("data")
    end

    def validate_purchase!(purchase)
      attributes = purchase.fetch("attributes")
      expected = {
        "productId" => PRODUCT_ID,
        "name" => REFERENCE_NAME,
        "inAppPurchaseType" => PURCHASE_TYPE,
        "familySharable" => false
      }
      mismatches = expected.filter_map do |key, value|
        actual = attributes[key]
        "#{key}=#{actual.inspect}（期望 #{value.inspect}）" unless actual == value
      end
      return if mismatches.empty?

      raise Error, "现有内购配置与计划不一致：#{mismatches.join('，')}"
    end

    def reconcile_purchase(purchase, write:)
      purchase_id = purchase.fetch("id")
      version = localization_version(purchase_id, write: write)
      if version.fetch(:resource)
        ensure_localizations(
          version.fetch(:resource).fetch("id"),
          write: write,
          version_writable: version.fetch(:writable)
        )
      else
        LOCALIZATIONS.each_key { |locale| @logger.message("计划创建内购本地化：#{locale}") }
      end
      {
        schedule: ensure_price_schedule(purchase_id, write: write),
        territory_count: ensure_availability(purchase_id, write: write)
      }
    end

    def localization_version(purchase_id, write:)
      versions = purchase_versions(purchase_id)
      draft = versions.find { |version| version.dig("attributes", "state") == "PREPARE_FOR_SUBMISSION" }
      selected = draft || versions.max_by { |version| version.dig("attributes", "version").to_i }
      if selected
        return {
          resource: selected,
          writable: selected.dig("attributes", "state") == "PREPARE_FOR_SUBMISSION"
        }
      end

      unless write
        @logger.message("计划创建内购可编辑版本")
        return { resource: nil, writable: true }
      end

      @logger.message("正在创建内购可编辑版本")
      begin
        response = @client.post(
          "/v1/inAppPurchaseVersions",
          body: {
            data: {
              type: "inAppPurchaseVersions",
              relationships: {
                inAppPurchase: {
                  data: { type: "inAppPurchases", id: purchase_id }
                }
              }
            }
          }
        )
        return { resource: response.fetch("data"), writable: true }
      rescue TokenWatchFastlane::AppStoreConnectAPIClient::Error => error
        # A timed-out or conflicting POST may still have created the unique draft version.
        recovered = poll_resource do
          purchase_versions(purchase_id).find do |version|
            version.dig("attributes", "state") == "PREPARE_FOR_SUBMISSION"
          end
        end
        return { resource: recovered, writable: true } if recovered

        raise error
      end
    end

    def purchase_versions(purchase_id)
      @client.get_all(
        "/v2/inAppPurchases/#{purchase_id}/versions",
        query: { "limit" => 200 }
      )
    end

    def ensure_localizations(version_id, write:, version_writable:)
      existing = @client.get_all(
        "/v1/inAppPurchaseVersions/#{version_id}/localizations",
        query: { "limit" => 200 }
      ).to_h { |localization| [localization.dig("attributes", "locale"), localization] }

      LOCALIZATIONS.each do |locale, metadata|
        localization = existing[locale]
        if localization
          validate_localization!(locale, localization.fetch("attributes"), metadata)
          @logger.message("复用内购本地化：#{locale}")
          next
        end

        unless write
          @logger.message("计划创建内购本地化：#{locale}")
          next
        end
        unless version_writable
          raise Error, "内购当前版本不可编辑，无法补充 #{locale} 本地化"
        end

        @logger.message("正在创建内购本地化：#{locale}")
        @client.post(
          "/v2/inAppPurchaseLocalizations",
          body: {
            data: {
              type: "inAppPurchaseLocalizations",
              attributes: {
                locale: locale,
                name: metadata.fetch(:name),
                description: metadata.fetch(:description)
              },
              relationships: {
                version: {
                  data: { type: "inAppPurchaseVersions", id: version_id }
                }
              }
            }
          }
        )
      end
    end

    def validate_localization!(locale, attributes, expected)
      actual = {
        name: attributes["name"],
        description: attributes["description"]
      }
      return if actual == expected

      raise Error, "#{locale} 内购文案与计划不一致；为避免覆盖线上资料，已停止执行"
    end

    def ensure_price_schedule(purchase_id, write:)
      schedule_response = stable_optional_get(
        "/v2/inAppPurchases/#{purchase_id}/iapPriceSchedule",
        query: { "include" => "baseTerritory" }
      )
      if schedule_response
        schedule = schedule_response.fetch("data")
        verify_base_territory!(schedule)
        verify_base_price!(schedule.fetch("id"))
        @logger.message("复用现有价格：#{BASE_TERRITORY} #{format_price(BASE_PRICE)}")
        return schedule
      end

      price_point = find_price_point(purchase_id, BASE_TERRITORY, BASE_PRICE)
      unless write
        @logger.message("计划设置基准价格：#{BASE_TERRITORY} #{format_price(BASE_PRICE)}")
        return nil
      end

      @logger.message("正在设置基准价格：#{BASE_TERRITORY} #{format_price(BASE_PRICE)}")
      response = @client.post(
        "/v1/inAppPurchasePriceSchedules",
        body: price_schedule_body(purchase_id, price_point.fetch("id"))
      )
      schedule = response.fetch("data")
      verify_base_price!(schedule.fetch("id"))
      schedule
    end

    def verify_base_territory!(schedule)
      territory_id = schedule.dig("relationships", "baseTerritory", "data", "id")
      return if territory_id == BASE_TERRITORY

      raise Error, "现有价格基准地区是 #{territory_id.inspect}，不是 #{BASE_TERRITORY}"
    end

    def find_price_point(purchase_id, territory, expected_price)
      points = @client.get_all(
        "/v2/inAppPurchases/#{purchase_id}/pricePoints",
        query: {
          "filter[territory]" => territory,
          "fields[inAppPurchasePricePoints]" => "customerPrice,proceeds,territory",
          "limit" => 8000
        }
      )
      matches = points.select do |point|
        decimal_price(point.dig("attributes", "customerPrice")) == expected_price
      end
      return matches.first if matches.one?

      raise Error, "#{territory} 找不到唯一的 #{format_price(expected_price)} IAP 价格点"
    end

    def price_schedule_body(purchase_id, price_point_id)
      # Apple requires inline-created JSON:API resources to use the literal ${local-id} form.
      temporary_price_id = "${price1}"
      {
        data: {
          type: "inAppPurchasePriceSchedules",
          relationships: {
            inAppPurchase: {
              data: { type: "inAppPurchases", id: purchase_id }
            },
            baseTerritory: {
              data: { type: "territories", id: BASE_TERRITORY }
            },
            manualPrices: {
              data: [{ type: "inAppPurchasePrices", id: temporary_price_id }]
            }
          }
        },
        included: [
          {
            type: "inAppPurchasePrices",
            id: temporary_price_id,
            attributes: { startDate: nil },
            relationships: {
              inAppPurchaseV2: {
                data: { type: "inAppPurchases", id: purchase_id }
              },
              inAppPurchasePricePoint: {
                data: { type: "inAppPurchasePricePoints", id: price_point_id }
              }
            }
          }
        ]
      }
    end

    def verify_base_price!(schedule_id)
      response = @client.get_paginated_document(
        "/v1/inAppPurchasePriceSchedules/#{schedule_id}/manualPrices",
        query: {
          "filter[territory]" => BASE_TERRITORY,
          "include" => "inAppPurchasePricePoint",
          "fields[inAppPurchasePrices]" => "startDate,endDate,inAppPurchasePricePoint,territory",
          "fields[inAppPurchasePricePoints]" => "customerPrice,proceeds,territory",
          "limit" => 200
        }
      )
      points_by_id = Array(response["included"]).filter_map do |resource|
        next unless resource["type"] == "inAppPurchasePricePoints"

        [resource.fetch("id"), decimal_price(resource.dig("attributes", "customerPrice"))]
      end.to_h
      today = Date.today
      prices = Array(response["data"])
      current_prices = prices.filter_map do |price|
        attributes = price.fetch("attributes", {})
        next unless price_active_on?(attributes, today)

        point_id = price.dig("relationships", "inAppPurchasePricePoint", "data", "id")
        points_by_id[point_id]
      end
      unless current_prices.any? && current_prices.all? { |price| price == BASE_PRICE }
        actual = current_prices.compact.map { |price| format_price(price) }
        raise Error, "现有 #{BASE_TERRITORY} 价格是 #{actual.join(', ')}，不是 #{format_price(BASE_PRICE)}"
      end

      future_mismatches = prices.filter_map do |price|
        attributes = price.fetch("attributes", {})
        start_date = parse_date(attributes["startDate"])
        end_date = parse_date(attributes["endDate"])
        next unless start_date && start_date > today
        next if end_date && end_date <= today

        point_id = price.dig("relationships", "inAppPurchasePricePoint", "data", "id")
        scheduled_price = points_by_id[point_id]
        next if scheduled_price == BASE_PRICE

        "#{start_date}: #{scheduled_price ? format_price(scheduled_price) : '未知价格'}"
      end
      return if future_mismatches.empty?

      raise Error, "存在非 #{format_price(BASE_PRICE)} 的未来价格：#{future_mismatches.join('，')}"
    end

    def ensure_availability(purchase_id, write:)
      desired = app_availability
      response = stable_optional_get("/v2/inAppPurchases/#{purchase_id}/inAppPurchaseAvailability")
      if response
        availability = response.fetch("data")
        territories = @client.get_all(
          "/v1/inAppPurchaseAvailabilities/#{availability.fetch('id')}/availableTerritories",
          query: { "limit" => 200 }
        )
        actual_territories = territories.map { |territory| territory.fetch("id") }.sort
        expected_territories = desired.fetch(:territories)
        actual_new_territories = availability.dig("attributes", "availableInNewTerritories") == true
        unless actual_territories == expected_territories &&
               actual_new_territories == desired.fetch(:available_in_new_territories)
          raise Error, "现有内购销售地区与 App 不一致；为避免覆盖线上配置，已停止执行"
        end

        @logger.message("复用现有销售地区：#{territories.length} 个")
        return territories.length
      end

      unless write
        @logger.message("计划设置销售地区：跟随 App 当前 #{desired.fetch(:territories).length} 个地区")
        return desired.fetch(:territories).length
      end

      @logger.message("正在设置销售地区：跟随 App 当前 #{desired.fetch(:territories).length} 个地区")
      @client.post(
        "/v1/inAppPurchaseAvailabilities",
        body: {
          data: {
            type: "inAppPurchaseAvailabilities",
            attributes: {
              availableInNewTerritories: desired.fetch(:available_in_new_territories)
            },
            relationships: {
              inAppPurchase: {
                data: { type: "inAppPurchases", id: purchase_id }
              },
              availableTerritories: {
                data: desired.fetch(:territories).map do |territory_id|
                  { type: "territories", id: territory_id }
                end
              }
            }
          }
        }
      )
      desired.fetch(:territories).length
    end

    def app_availability
      response = @client.get("/v1/apps/#{@app_id}/appAvailabilityV2")
      availability = response.fetch("data")
      territory_availabilities = @client.get_all(
        "/v2/appAvailabilities/#{availability.fetch('id')}/territoryAvailabilities",
        query: { "include" => "territory", "limit" => 200 }
      )
      territory_ids = territory_availabilities.filter_map do |item|
        next unless item.dig("attributes", "available")

        item.dig("relationships", "territory", "data", "id")
      end
      raise Error, "App 当前没有可复制给内购的销售地区" if territory_ids.empty?

      {
        available_in_new_territories: availability.dig("attributes", "availableInNewTerritories") == true,
        territories: territory_ids.sort
      }
    end

    def automatic_price(schedule_id, territory)
      response = @client.get_paginated_document(
        "/v1/inAppPurchasePriceSchedules/#{schedule_id}/automaticPrices",
        query: {
          "filter[territory]" => territory,
          "include" => "inAppPurchasePricePoint",
          "fields[inAppPurchasePricePoints]" => "customerPrice,proceeds,territory",
          "limit" => 200
        }
      )
      points_by_id = Array(response["included"]).filter_map do |resource|
        next unless resource["type"] == "inAppPurchasePricePoints"

        [resource.fetch("id"), decimal_price(resource.dig("attributes", "customerPrice"))]
      end.to_h
      today = Date.today
      prices = Array(response["data"]).filter_map do |price|
        next unless price_active_on?(price.fetch("attributes", {}), today)

        point_id = price.dig("relationships", "inAppPurchasePricePoint", "data", "id")
        points_by_id[point_id]
      end.uniq
      prices.one? ? format_price(prices.first) : prices.map { |price| format_price(price) }.join(", ")
    end

    def stable_optional_get(path, query: nil)
      # Relationship endpoints can briefly return 404 while a new IAP propagates.
      3.times do |attempt|
        response = @client.get_optional(path, query: query)
        return response if response

        sleep 2 if attempt < 2
      end
      nil
    end

    def poll_resource
      10.times do |attempt|
        resource = yield
        return resource if resource

        sleep 2 if attempt < 9
      end
      nil
    end

    def decimal_price(value)
      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def format_price(price)
      format("%.2f", price)
    end

    def parse_date(value)
      Date.iso8601(value) unless value.nil? || value.empty?
    end

    def price_active_on?(attributes, date)
      start_date = parse_date(attributes["startDate"])
      end_date = parse_date(attributes["endDate"])
      (start_date.nil? || start_date <= date) && (end_date.nil? || date < end_date)
    end
  end
end
