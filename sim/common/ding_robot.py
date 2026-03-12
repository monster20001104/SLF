import os
import hmac
import hashlib
import base64
import urllib.parse
import requests
import json
import time

from cocotb.regression import RegressionManager
from cocotb.utils import get_sim_time, want_color_output
import cocotb.ANSI as ANSI

# text = None


def ding_robot(
    path="~/.ding_robot.json",
    proxies={
        'http': 'http://192.168.100.1:8668',
        'https': 'http://192.168.100.1:8668',
    },
):
    global cfg_path
    global cfg_proxies
    cfg_path = path
    cfg_proxies = proxies
    RegressionManager._log_test_summary = patched_log_test_summary
    print("RegressionManager._log_test_summary changed")


def send_custom_robot_group_message(access_token=None, secret=None, msg="hello world!", at_user_ids=None, at_mobiles=None, is_at_all=False):
    if access_token == None:
        with open(os.path.expanduser(cfg_path), "r") as f:
            config = json.load(f)
            access_token = config["access_token"]
            secret = config["secret"]
            at_mobiles = config.get("at_mobiles", at_mobiles)
    timestamp = str(round(time.time() * 1000))
    string_to_sign = f'{timestamp}\n{secret}'
    hmac_code = hmac.new(secret.encode('utf-8'), string_to_sign.encode('utf-8'), digestmod=hashlib.sha256).digest()
    sign = urllib.parse.quote_plus(base64.b64encode(hmac_code))
    url = f'https://oapi.dingtalk.com/robot/send?access_token={access_token}&timestamp={timestamp}&sign={sign}'
    cfg_proxies = {
        'http': 'http://192.168.100.1:8668',
        'https': 'http://192.168.100.1:8668',
    }
    body = {
        "at": {"isAtAll": str(is_at_all).lower(), "atUserIds": at_user_ids or [], "atMobiles": at_mobiles or []},
        "text": {"content": msg},
        "msgtype": "text",
    }
    headers = {'Content-Type': 'application/json'}
    resp = requests.post(url, json=body, headers=headers, proxies=cfg_proxies)
    return resp.json()


def patched_log_test_summary(self):
    # def _log_test_summary(self) -> None:

    real_time = time.time() - self.start_time
    sim_time_ns = get_sim_time("ns")
    ratio_time = self._safe_divide(sim_time_ns, real_time)

    if len(self.test_results) == 0:
        return

    TEST_FIELD = "TEST"
    RESULT_FIELD = "STATUS"
    SIM_FIELD = "SIM TIME (ns)"
    REAL_FIELD = "REAL TIME (s)"
    RATIO_FIELD = "RATIO (ns/s)"
    TOTAL_NAME = f"TESTS={self.ntests} PASS={self.passed} FAIL={self.failures} SKIP={self.skipped}"

    TEST_FIELD_LEN = max(
        len(TEST_FIELD),
        len(TOTAL_NAME),
        len(max([x["test"] for x in self.test_results], key=len)),
    )
    RESULT_FIELD_LEN = len(RESULT_FIELD)
    SIM_FIELD_LEN = len(SIM_FIELD)
    REAL_FIELD_LEN = len(REAL_FIELD)
    RATIO_FIELD_LEN = len(RATIO_FIELD)

    header_dict = dict(
        a=TEST_FIELD,
        b=RESULT_FIELD,
        c=SIM_FIELD,
        d=REAL_FIELD,
        e=RATIO_FIELD,
        a_len=TEST_FIELD_LEN,
        b_len=RESULT_FIELD_LEN,
        c_len=SIM_FIELD_LEN,
        d_len=REAL_FIELD_LEN,
        e_len=RATIO_FIELD_LEN,
    )

    LINE_LEN = 3 + TEST_FIELD_LEN + 2 + RESULT_FIELD_LEN + 2 + SIM_FIELD_LEN + 2 + REAL_FIELD_LEN + 2 + RATIO_FIELD_LEN + 3

    LINE_SEP = "*" * LINE_LEN + "\n"

    summary = ""
    summary += LINE_SEP
    summary += "** {a:<{a_len}}  {b:^{b_len}}  {c:>{c_len}}  {d:>{d_len}}  {e:>{e_len}} **\n".format(**header_dict)
    summary += LINE_SEP

    test_line = "** {a:<{a_len}}  {start}{b:^{b_len}}{end}  {c:>{c_len}.2f}   {d:>{d_len}.2f}   {e:>{e_len}}  **\n"
    for result in self.test_results:
        hilite = ""
        lolite = ""

        if result["pass"] is None:
            ratio = "-.--"
            pass_fail_str = "SKIP"
            if want_color_output():
                hilite = ANSI.COLOR_SKIPPED
                lolite = ANSI.COLOR_DEFAULT
        elif result["pass"]:
            ratio = format(result["ratio"], "0.2f")
            pass_fail_str = "PASS"
            if want_color_output():
                hilite = ANSI.COLOR_PASSED
                lolite = ANSI.COLOR_DEFAULT
        else:
            ratio = format(result["ratio"], "0.2f")
            pass_fail_str = "FAIL"
            if want_color_output():
                hilite = ANSI.COLOR_FAILED
                lolite = ANSI.COLOR_DEFAULT

        test_dict = dict(
            a=result["test"],
            b=pass_fail_str,
            c=result["sim"],
            d=result["real"],
            e=ratio,
            a_len=TEST_FIELD_LEN,
            b_len=RESULT_FIELD_LEN,
            c_len=SIM_FIELD_LEN - 1,
            d_len=REAL_FIELD_LEN - 1,
            e_len=RATIO_FIELD_LEN - 1,
            start=hilite,
            end=lolite,
        )

        summary += test_line.format(**test_dict)

    summary += LINE_SEP

    summary += test_line.format(
        a=TOTAL_NAME,
        b="",
        c=sim_time_ns,
        d=real_time,
        e=format(ratio_time, "0.2f"),
        a_len=TEST_FIELD_LEN,
        b_len=RESULT_FIELD_LEN,
        c_len=SIM_FIELD_LEN - 1,
        d_len=REAL_FIELD_LEN - 1,
        e_len=RATIO_FIELD_LEN - 1,
        start="",
        end="",
    )

    summary += LINE_SEP

    self.log.info(summary)
    # if len(self.test_results) > 1:
    summary = summary.replace(ANSI.COLOR_SKIPPED, "")
    summary = summary.replace(ANSI.COLOR_PASSED, "")
    summary = summary.replace(ANSI.COLOR_FAILED, "")
    summary = summary.replace(ANSI.COLOR_DEFAULT, "")
    send_custom_robot_group_message(msg="sim path:" + os.getcwd() + "\n" + summary)
