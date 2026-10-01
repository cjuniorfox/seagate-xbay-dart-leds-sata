// SPDX-License-Identifier: GPL-2.0

#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pinctrl/consumer.h>
#include <linux/property.h>
#include <linux/slab.h>
#include <linux/leds.h>
#include <linux/gpio/consumer.h>
#include <linux/mutex.h>

enum dart_led_mode {
	DART_LED_GPIO,
	DART_LED_SATA,
};

struct dart_led {
	struct led_classdev led_cdev;
	struct gpio_desc *gpiod;

	struct pinctrl *pinctrl;
	struct pinctrl_state *sata_state;
	struct pinctrl_state *gpio_state;

	enum dart_led_mode mode;
	struct mutex lock;
};

struct dart_leds {
	int num_leds;
	struct dart_led leds[];
};

static ssize_t sata_show(struct device *dev,
			 struct device_attribute *attr,
			 char *buf)
{
	struct led_classdev *led_cdev = dev_get_drvdata(dev);
	struct dart_led *led =
		container_of(led_cdev, struct dart_led, led_cdev);
	bool sata_mode;

	mutex_lock(&led->lock);
	sata_mode = led->mode == DART_LED_SATA;
	mutex_unlock(&led->lock);

	return sysfs_emit(buf, "%d\n", sata_mode);
}

static ssize_t sata_store(struct device *dev,
			  struct device_attribute *attr,
			  const char *buf, size_t count)
{
	struct led_classdev *led_cdev = dev_get_drvdata(dev);
	struct dart_led *led =
		container_of(led_cdev, struct dart_led, led_cdev);
	bool sata_mode;
	int ret;

	ret = kstrtobool(buf, &sata_mode);
	if (ret)
		return ret;

	mutex_lock(&led->lock);

	if (sata_mode) {
		if (led->led_cdev.brightness != LED_OFF)
			ret = pinctrl_select_state(led->pinctrl,
							led->sata_state);
		else
			ret = pinctrl_select_state(led->pinctrl,
							led->gpio_state);
		if (!ret)
			led->mode = DART_LED_SATA;
	} else {
		ret = pinctrl_select_state(led->pinctrl, led->gpio_state);
		if (!ret) {
			gpiod_set_value_cansleep(led->gpiod,
						led->led_cdev.brightness != LED_OFF);
			led->mode = DART_LED_GPIO;
		}
	}

	mutex_unlock(&led->lock);

	if (ret)
		return ret;

	return count;
}

static DEVICE_ATTR_RW(sata);

static struct attribute *dart_led_attrs[] = {
	&dev_attr_sata.attr,
	NULL,
};

static const struct attribute_group dart_led_attr_group = {
	.attrs = dart_led_attrs,
};

static const struct attribute_group *dart_led_groups[] = {
	&dart_led_attr_group,
	NULL,
};

static int dart_leds_brightness_set(struct led_classdev *led_cdev,
				    enum led_brightness brightness)
{
	struct dart_led *led =
		container_of(led_cdev, struct dart_led, led_cdev);
	int ret;

	mutex_lock(&led->lock);

	if (brightness == LED_OFF) {
		ret = pinctrl_select_state(led->pinctrl, led->gpio_state);
		if (ret)
			goto out_unlock;

		gpiod_set_value_cansleep(led->gpiod, 0);
	} else if (led->mode == DART_LED_SATA) {
		ret = pinctrl_select_state(led->pinctrl, led->sata_state);
		if (ret)
			goto out_unlock;
	} else {
		ret = pinctrl_select_state(led->pinctrl, led->gpio_state);
		if (ret)
			goto out_unlock;

		gpiod_set_value_cansleep(led->gpiod, 1);
	}

out_unlock:
	mutex_unlock(&led->lock);

	return ret;
}

static int dart_led_register(struct device *dev, struct fwnode_handle *fwnode,
			     struct dart_led *led)
{
	struct led_init_data init_data = {
		.fwnode = fwnode,
	};
	int ret;

	led->led_cdev.groups = dart_led_groups;
	led->led_cdev.brightness_set_blocking = dart_leds_brightness_set;

	led->gpiod = devm_fwnode_gpiod_get(dev, fwnode, NULL, GPIOD_ASIS, NULL);
	if (IS_ERR(led->gpiod))
		return dev_err_probe(dev, PTR_ERR(led->gpiod),
				     "failed to get GPIO '%pfw'\n", fwnode);

	led->led_cdev.brightness = LED_FULL;

	ret = devm_led_classdev_register_ext(dev, &led->led_cdev, &init_data);
	if (ret)
		return dev_err_probe(dev, ret,
				     "failed to register LED for node %pfw\n",
				     fwnode);

	/*
	 * The LED class device owns the child fwnode, so use it as the
	 * pinctrl consumer to obtain the child's independent pinctrl states.
	 */
	led->pinctrl = devm_pinctrl_get(led->led_cdev.dev);
	if (IS_ERR(led->pinctrl))
		return dev_err_probe(dev, PTR_ERR(led->pinctrl),
				"failed to get pinctrl for %pfw\n",
				fwnode);

	led->sata_state =
		pinctrl_lookup_state(led->pinctrl, PINCTRL_STATE_DEFAULT);
	if (IS_ERR(led->sata_state))
		return dev_err_probe(dev, PTR_ERR(led->sata_state),
				     "failed to get SATA state for %pfw\n",
				     fwnode);

	led->gpio_state = pinctrl_lookup_state(led->pinctrl, "gpio");
	if (IS_ERR(led->gpio_state))
		return dev_err_probe(dev, PTR_ERR(led->gpio_state),
				     "failed to get GPIO state for %pfw\n",
				     fwnode);

	ret = pinctrl_select_state(led->pinctrl, led->sata_state);
	if (ret)
		return dev_err_probe(dev, ret,
				     "failed to select SATA pinctrl state for %pfw\n",
				     fwnode);
	led->mode = DART_LED_SATA;

	return 0;
}

static int dart_leds_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct fwnode_handle *child;
	struct dart_leds *leds;
	int count;
	int i = 0;
	int ret;

	count = device_get_child_node_count(dev);
	if (!count)
		return -ENODEV;

	leds = devm_kzalloc(dev, struct_size(leds, leds, count), GFP_KERNEL);
	if (!leds)
		return -ENOMEM;

	leds->num_leds = count;

	device_for_each_child_node(dev, child) {
		struct dart_led *led = &leds->leds[i];

		mutex_init(&led->lock);

		ret = dart_led_register(dev, child, led);
		if (ret) {
			fwnode_handle_put(child);
			return ret;
		}

		i++;
	}

	dev_info(dev, "Dart LED pinctrl initialized\n");

	return 0;
}

static const struct of_device_id dart_leds_of_match[] = {
	{ .compatible = "seagate,dart-leds" },
	{}
};

MODULE_DEVICE_TABLE(of, dart_leds_of_match);

static struct platform_driver dart_leds_driver = {
	.probe = dart_leds_probe,
	.driver = {
		.name = "dart-leds",
		.of_match_table = dart_leds_of_match,
	},
};

module_platform_driver(dart_leds_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Carlos Anselmo Mendes Junior");
MODULE_DESCRIPTION("LED Driver for Seagate DART Platform");
