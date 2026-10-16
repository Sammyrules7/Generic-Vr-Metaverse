package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"vr.maio-tech.com/server/protocol"
)

const defaultTurnTTLHours = 24

// turnConfig is loaded once at startup. An empty secret disables the relay:
// join replies carry no credentials and clients stay STUN-only.
type turnConfig struct {
	secret string
	urls   []string
	ttl    time.Duration
}

var turn = loadTurnConfig()

func loadTurnConfig() turnConfig {
	ttlHours := defaultTurnTTLHours
	if raw := strings.TrimSpace(os.Getenv("VR_PLATFORM_TURN_TTL_HOURS")); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
			ttlHours = parsed
		}
	}
	var urls []string
	for _, url := range strings.Split(os.Getenv("VR_PLATFORM_TURN_URLS"), ",") {
		if trimmed := strings.TrimSpace(url); trimmed != "" {
			urls = append(urls, trimmed)
		}
	}
	return turnConfig{
		secret: os.Getenv("VR_PLATFORM_TURN_SECRET"),
		urls:   urls,
		ttl:    time.Duration(ttlHours) * time.Hour,
	}
}

// mintTurnCredentials derives a time-boxed TURN username/password pair using
// the standard TURN REST API scheme: the username embeds expiry, the password
// is base64(HMAC-SHA1(shared_secret, username)). coturn validates these with
// static-auth-secret, so no per-user state exists on either side and a coturn
// restart (which wipes allocations but keeps the secret) needs no credential
// refresh — clients simply re-allocate with unexpired credentials.
func mintTurnCredentials(now time.Time, clientID uint32) *protocol.TurnCredentials {
	if turn.secret == "" || len(turn.urls) == 0 {
		return nil
	}
	expiry := now.Add(turn.ttl).Unix()
	username := fmt.Sprintf("%d:%d", expiry, clientID)
	mac := hmac.New(sha1.New, []byte(turn.secret))
	mac.Write([]byte(username))
	return &protocol.TurnCredentials{
		Urls:     turn.urls,
		Username: username,
		Password: base64.StdEncoding.EncodeToString(mac.Sum(nil)),
		Ttl:      uint32(turn.ttl / time.Second),
	}
}
